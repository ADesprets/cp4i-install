# Déploiement PostgreSQL avec Crunchy Operator pour WAS Liberty

## Vue d'ensemble

Ce guide décrit le déploiement d'une base de données PostgreSQL dans OpenShift en utilisant le **Crunchy PostgreSQL Operator** pour supporter l'API REST Order Management avec persistance.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                         │
│                                                              │
│  ┌────────────────────┐         ┌─────────────────────┐    │
│  │  WAS Liberty Pod   │         │  PostgreSQL Cluster │    │
│  │                    │         │                     │    │
│  │  RestApplicationP  │────────▶│  orders-postgres    │    │
│  │  (OrderResourceP)  │  JDBC   │  - Primary          │    │
│  │                    │         │  - PgBouncer        │    │
│  └────────────────────┘         │  - Backup (repo1)   │    │
│                                 └─────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Prérequis

### 1. Installer Crunchy PostgreSQL Operator

L'opérateur doit être installé depuis le catalogue **certified-operators** :

```bash
# Vérifier si l'opérateur est disponible
oc get packagemanifests -n openshift-marketplace | grep postgres

# Créer une Subscription pour installer l'opérateur
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: crunchy-postgres-operator
  namespace: openshift-operators
spec:
  channel: v5
  name: crunchy-postgres-operator
  source: certified-operators
  sourceNamespace: openshift-marketplace
EOF

# Vérifier l'installation
oc get csv -n openshift-operators | grep postgres
```

### 2. Créer le namespace

```bash
export VAR_WASLIBERTY_NAMESPACE="was-liberty"
oc create namespace $VAR_WASLIBERTY_NAMESPACE
```

## Fichiers créés

### 1. Script SQL d'initialisation
**Fichier** : `resources/init-orders-db.sql`
- Crée la table `orders`
- Crée les index pour les performances
- Insère des données de test

### 2. Template PostgresCluster
**Fichier** : `tmpl/postgres-cluster.yaml`
- ConfigMap avec le script d'initialisation
- PostgresCluster CR avec :
  - PostgreSQL 16
  - 1 instance (réplica)
  - PgBouncer pour le connection pooling
  - Backup avec pgBackRest
  - Monitoring avec pgmonitor
  - Utilisateur `ordersuser` avec base `ordersdb`

### 3. Configuration Liberty
**Fichier** : `resources/server.xml`
- DataSource JDBC configuré pour PostgreSQL
- Variables d'environnement pour la connexion
- Support SSL/TLS
- Connection pooling optimisé

### 4. Template WebSphereLibertyApplication
**Fichier** : `tmpl/WAS-WLApp-postgres.yaml`
- Variables d'environnement pour PostgreSQL
- Secrets montés pour credentials
- Certificats SSL montés

## Déploiement automatique

### Utilisation du script was.config.sh

Le script `scripts/was.config.sh` a été enrichi avec la fonction `deploy_postgresql()` :

```bash
# Déployer uniquement PostgreSQL
cd demos/was_liberty/scripts
./was.config.sh --call deploy_postgresql

# Déployer tout (PostgreSQL + Application)
./was.config.sh --all
```

### Fonction deploy_postgresql

La fonction effectue les actions suivantes :
1. Crée le ConfigMap avec le script d'initialisation
2. Déploie le PostgresCluster CR
3. Attend que le cluster soit prêt
4. Affiche les informations de connexion

## Déploiement manuel

### Étape 1 : Déployer PostgreSQL

```bash
cd demos/was_liberty

# Substituer les variables et appliquer
export VAR_WASLIBERTY_NAMESPACE="was-liberty"
envsubst < tmpl/postgres-cluster.yaml | oc apply -f -

# Vérifier le déploiement
oc get postgrescluster -n $VAR_WASLIBERTY_NAMESPACE
oc get pods -n $VAR_WASLIBERTY_NAMESPACE | grep postgres
```

### Étape 2 : Attendre que le cluster soit prêt

```bash
# Surveiller le statut
oc get postgrescluster orders-postgres -n $VAR_WASLIBERTY_NAMESPACE -w

# Vérifier les conditions
oc get postgrescluster orders-postgres -n $VAR_WASLIBERTY_NAMESPACE -o jsonpath='{.status.conditions[*].type}'
```

### Étape 3 : Récupérer les informations de connexion

```bash
# Récupérer le mot de passe
oc get secret orders-postgres-pguser-ordersuser -n $VAR_WASLIBERTY_NAMESPACE \
  -o jsonpath='{.data.password}' | base64 -d

# Récupérer l'utilisateur
oc get secret orders-postgres-pguser-ordersuser -n $VAR_WASLIBERTY_NAMESPACE \
  -o jsonpath='{.data.user}' | base64 -d

# Récupérer l'URL JDBC complète
oc get secret orders-postgres-pguser-ordersuser -n $VAR_WASLIBERTY_NAMESPACE \
  -o jsonpath='{.data.jdbc-uri}' | base64 -d
```

## Informations de connexion

### Services créés par Crunchy Operator

| Service | Port | Description |
|---------|------|-------------|
| `orders-postgres-primary` | 5432 | Instance PostgreSQL primaire |
| `orders-postgres-replicas` | 5432 | Réplicas en lecture seule |
| `orders-postgres-pgbouncer` | 5432 | Connection pooler |

### Paramètres de connexion

- **Host** : `orders-postgres-primary.${VAR_WASLIBERTY_NAMESPACE}.svc`
- **Port** : `5432`
- **Database** : `ordersdb`
- **User** : `ordersuser`
- **Password** : Stocké dans le secret `orders-postgres-pguser-ordersuser`

### URL JDBC

```
jdbc:postgresql://orders-postgres-primary.${VAR_WASLIBERTY_NAMESPACE}.svc:5432/ordersdb
```

## Configuration de l'application Liberty

### Variables d'environnement injectées

Le template `WAS-WLApp-postgres.yaml` injecte automatiquement :

```yaml
env:
  - name: POSTGRES_HOST
    value: "orders-postgres-primary.${VAR_WASLIBERTY_NAMESPACE}.svc"
  - name: POSTGRES_PORT
    value: "5432"
  - name: POSTGRES_DATABASE
    value: "ordersdb"
  - name: POSTGRES_USER
    valueFrom:
      secretKeyRef:
        name: orders-postgres-pguser-ordersuser
        key: user
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: orders-postgres-pguser-ordersuser
        key: password
```

### DataSource dans server.xml

Le fichier `server.xml` utilise ces variables :

```xml
<dataSource id="ordersDS" jndiName="jdbc/ordersDB">
    <jdbcDriver libraryRef="PostgreSQLLib"/>
    <properties.postgresql 
        serverName="${env.POSTGRES_HOST}"
        portNumber="${env.POSTGRES_PORT}"
        databaseName="${env.POSTGRES_DATABASE}"
        user="${env.POSTGRES_USER}"
        password="${env.POSTGRES_PASSWORD}"
        ssl="true"
        sslmode="require"/>
</dataSource>
```

## Mise à jour du Dockerfile

Le Dockerfile doit être modifié pour inclure :

1. Le driver PostgreSQL JDBC
2. Le fichier server.xml configuré

```dockerfile
# Copier le driver PostgreSQL
COPY --chown=1001:0 target/postgresql-42.7.4.jar /config/lib/

# Copier la configuration server.xml
COPY --chown=1001:0 resources/server.xml /config/
```

## Tests de connexion

### Test depuis un pod PostgreSQL

```bash
# Se connecter au pod PostgreSQL
oc exec -it orders-postgres-instance1-xxxx -n $VAR_WASLIBERTY_NAMESPACE -- bash

# Se connecter à la base
psql -U ordersuser -d ordersdb

# Vérifier les tables
\dt

# Vérifier les données
SELECT COUNT(*) FROM orders;
SELECT * FROM orders LIMIT 5;
```

### Test depuis l'application Liberty

```bash
# Vérifier les logs de l'application
oc logs -f deployment/${MY_WASLIBERTY_APP_NAME} -n $VAR_WASLIBERTY_NAMESPACE

# Tester l'endpoint health
curl http://<liberty-route>/demo/apip/orderp/health

# Tester la récupération des commandes
curl http://<liberty-route>/demo/apip/orderp
```

## Monitoring et maintenance

### Vérifier l'état du cluster

```bash
# État général
oc get postgrescluster orders-postgres -n $VAR_WASLIBERTY_NAMESPACE

# Pods PostgreSQL
oc get pods -n $VAR_WASLIBERTY_NAMESPACE -l postgres-operator.crunchydata.com/cluster=orders-postgres

# PVC (stockage)
oc get pvc -n $VAR_WASLIBERTY_NAMESPACE | grep postgres
```

### Logs PostgreSQL

```bash
# Logs de l'instance primaire
oc logs -f orders-postgres-instance1-xxxx -n $VAR_WASLIBERTY_NAMESPACE

# Logs PgBouncer
oc logs -f orders-postgres-pgbouncer-xxxx -n $VAR_WASLIBERTY_NAMESPACE
```

### Backups

Les backups sont automatiquement configurés avec pgBackRest :

```bash
# Vérifier les backups
oc get postgrescluster orders-postgres -n $VAR_WASLIBERTY_NAMESPACE \
  -o jsonpath='{.status.pgbackrest.repos[0]}'

# Déclencher un backup manuel
oc annotate postgrescluster orders-postgres -n $VAR_WASLIBERTY_NAMESPACE \
  postgres-operator.crunchydata.com/pgbackrest-backup="$(date)"
```

## Scaling

### Ajouter des réplicas

Modifier le PostgresCluster CR :

```yaml
spec:
  instances:
    - name: instance1
      replicas: 3  # Augmenter le nombre de réplicas
```

Appliquer :
```bash
oc apply -f tmpl/postgres-cluster.yaml -n $VAR_WASLIBERTY_NAMESPACE
```

## Troubleshooting

### Problème : Cluster ne démarre pas

```bash
# Vérifier les events
oc get events -n $VAR_WASLIBERTY_NAMESPACE --sort-by='.lastTimestamp'

# Vérifier les logs de l'opérateur
oc logs -n openshift-operators deployment/pgo -f
```

### Problème : Application ne peut pas se connecter

```bash
# Vérifier que le secret existe
oc get secret orders-postgres-pguser-ordersuser -n $VAR_WASLIBERTY_NAMESPACE

# Vérifier les variables d'environnement du pod Liberty
oc exec deployment/${MY_WASLIBERTY_APP_NAME} -n $VAR_WASLIBERTY_NAMESPACE -- env | grep POSTGRES

# Tester la connectivité réseau
oc exec deployment/${MY_WASLIBERTY_APP_NAME} -n $VAR_WASLIBERTY_NAMESPACE -- \
  nc -zv orders-postgres-primary.${VAR_WASLIBERTY_NAMESPACE}.svc 5432
```

### Problème : Erreur SSL/TLS

```bash
# Vérifier que le certificat est monté
oc exec deployment/${MY_WASLIBERTY_APP_NAME} -n $VAR_WASLIBERTY_NAMESPACE -- \
  ls -la /etc/postgres-certs/

# Désactiver temporairement SSL pour tester
# Modifier server.xml : ssl="false"
```

## Nettoyage

```bash
# Supprimer le cluster PostgreSQL
oc delete postgrescluster orders-postgres -n $VAR_WASLIBERTY_NAMESPACE

# Supprimer le ConfigMap
oc delete configmap orders-db-init -n $VAR_WASLIBERTY_NAMESPACE

# Supprimer les PVC (attention : perte de données)
oc delete pvc -n $VAR_WASLIBERTY_NAMESPACE -l postgres-operator.crunchydata.com/cluster=orders-postgres
```

## Références

- [Crunchy PostgreSQL Operator Documentation](https://access.crunchydata.com/documentation/postgres-operator/latest/)
- [PostgreSQL on OpenShift](https://www.postgresql.org/docs/16/)
- [WebSphere Liberty DataSource Configuration](https://www.ibm.com/docs/en/was-liberty/base?topic=liberty-configuring-relational-database-connectivity-in)
