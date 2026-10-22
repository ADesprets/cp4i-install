

# API REST Order avec Persistance PostgreSQL

## Vue d'ensemble

Cette application fournit une API REST complète pour la gestion des commandes (Orders) avec persistance dans une base de données PostgreSQL.

## Architecture

### Composants créés

1. **RestApplicationP.java** - Application REST exposée sur `/apip`
2. **OrderResourceP.java** - Ressource REST avec opérations CRUD complètes
3. **OrderService.java** - Service de persistance avec gestion transactionnelle
4. **OrderEntity.java** - Entité JPA mappée à la table `orders`
5. **persistence.xml** - Configuration JPA avec unité de persistance `ordersPU`

### Endpoints disponibles

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| POST | `/apip/orderp` | Créer une nouvelle commande |
| GET | `/apip/orderp/{orderId}` | Récupérer une commande par ID |
| GET | `/apip/orderp` | Récupérer toutes les commandes (avec pagination) |
| GET | `/apip/orderp?offset=0&limit=10` | Récupérer avec pagination |
| GET | `/apip/orderp?customerId={id}` | Filtrer par ID client |
| GET | `/apip/orderp?region={region}` | Filtrer par région |
| PUT | `/apip/orderp/{orderId}` | Mettre à jour une commande |
| DELETE | `/apip/orderp/{orderId}` | Supprimer une commande |
| GET | `/apip/orderp/count` | Compter les commandes |
| GET | `/apip/orderp/health` | Vérifier l'état du service |

## Configuration PostgreSQL

### 1. Créer la base de données

```sql
CREATE DATABASE ordersdb;
CREATE USER ordersuser WITH PASSWORD 'orderspass';
GRANT ALL PRIVILEGES ON DATABASE ordersdb TO ordersuser;
```

### 2. Schéma de la table (créé automatiquement par JPA)

```sql
CREATE TABLE orders (
    id VARCHAR(36) PRIMARY KEY,
    customerid VARCHAR(36) NOT NULL,
    customer VARCHAR(255) NOT NULL,
    description VARCHAR(500) NOT NULL,
    price DOUBLE PRECISION NOT NULL,
    quantity INTEGER NOT NULL,
    region VARCHAR(50) NOT NULL,
    ordertime TIMESTAMP NOT NULL
);
```

### 3. Configuration Liberty (server.xml)

Ajouter la datasource JDBC dans votre `server.xml` :

```xml
<server>
    <!-- Features -->
    <featureManager>
        <feature>jakartaee-10.0</feature>
        <feature>jdbc-4.3</feature>
        <feature>jpa-3.1</feature>
    </featureManager>

    <!-- PostgreSQL Library -->
    <library id="PostgreSQLLib">
        <fileset dir="${shared.resource.dir}/postgresql" includes="*.jar"/>
    </library>

    <!-- DataSource -->
    <dataSource id="ordersDS" jndiName="jdbc/ordersDB">
        <jdbcDriver libraryRef="PostgreSQLLib"/>
        <properties.postgresql 
            serverName="localhost"
            portNumber="5432"
            databaseName="ordersdb"
            user="ordersuser"
            password="orderspass"/>
    </dataSource>

    <!-- Connection Manager -->
    <connectionManager id="ConMgr1" 
        maxPoolSize="10" 
        minPoolSize="2"/>
</server>
```

### 4. Copier le driver PostgreSQL

Copier `postgresql-42.7.4.jar` dans :
```
${WLP_HOME}/usr/shared/resources/postgresql/
```

## Exemples d'utilisation

### Créer une commande

```bash
curl -X POST http://localhost:9080/demo/apip/orderp \
  -H "Content-Type: application/json" \
  -d '{
    "customerid": "cust-123",
    "customer": "John Doe",
    "description": "Laptop Computer",
    "price": 1299.99,
    "quantity": 1,
    "region": "EMEA"
  }'
```

### Récupérer une commande

```bash
curl http://localhost:9080/demo/apip/orderp/{orderId}
```

### Récupérer toutes les commandes

```bash
# Sans pagination (toutes les commandes)
curl http://localhost:9080/demo/apip/orderp

# Avec pagination (10 premières commandes)
curl http://localhost:9080/demo/apip/orderp?offset=0&limit=10

# Page suivante (commandes 11-20)
curl http://localhost:9080/demo/apip/orderp?offset=10&limit=10
```

**Headers de réponse pour la pagination :**
- `X-Total-Count` : Nombre total de commandes en base
- `X-Returned-Count` : Nombre de commandes retournées dans cette réponse
- `X-Offset` : Offset utilisé
- `X-Limit` : Limite utilisée

### Filtrer par client

```bash
curl http://localhost:9080/demo/apip/orderp?customerId=cust-123
```

### Mettre à jour une commande

```bash
curl -X PUT http://localhost:9080/demo/apip/orderp/{orderId} \
  -H "Content-Type: application/json" \
  -d '{
    "customerid": "cust-123",
    "customer": "John Doe",
    "description": "Updated Laptop",
    "price": 1399.99,
    "quantity": 2,
    "region": "EMEA"
  }'
```

### Supprimer une commande

```bash
curl -X DELETE http://localhost:9080/demo/apip/orderp/{orderId}
```

### Compter les commandes

```bash
curl http://localhost:9080/demo/apip/orderp/count
```

## Dépendances Maven ajoutées

```xml
<dependency>
    <groupId>jakarta.persistence</groupId>
    <artifactId>jakarta.persistence-api</artifactId>
    <version>3.1.0</version>
    <scope>provided</scope>
</dependency>
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <version>42.7.4</version>
</dependency>
<dependency>
    <groupId>jakarta.transaction</groupId>
    <artifactId>jakarta.transaction-api</artifactId>
    <version>2.0.1</version>
    <scope>provided</scope>
</dependency>
```

## Logging

Le service utilise `java.util.logging.Logger` pour tracer les opérations :
- Création de commandes
- Récupération de commandes
- Mise à jour de commandes
- Suppression de commandes
- Erreurs et exceptions

## Gestion des erreurs

L'API retourne des codes HTTP appropriés :
- `200 OK` - Opération réussie
- `201 Created` - Commande créée
- `400 Bad Request` - Données invalides
- `404 Not Found` - Commande non trouvée
- `500 Internal Server Error` - Erreur serveur

## Notes importantes

1. **Transaction Management** : Toutes les opérations d'écriture (CREATE, UPDATE, DELETE) sont transactionnelles via `@Transactional`
2. **ID Generation** : Les IDs sont générés automatiquement si non fournis (UUID)
3. **Timestamp** : Le champ `ordertime` est automatiquement défini à la création
4. **Named Queries** : Utilisation de requêtes nommées pour les recherches optimisées
5. **DTO Conversion** : Conversion automatique entre `Order` (DTO) et `OrderEntity` (JPA)

## Différences avec l'API originale

| Aspect | API Originale (`/api/order`) | Nouvelle API (`/apip/orderp`) |
|--------|------------------------------|-------------------------------|
| Persistance | Aucune (génération à la volée) | PostgreSQL via JPA |
| Opérations | GET uniquement | CRUD complet |
| Données | Générées avec Faker | Stockées en base |
| Transactions | N/A | Gestion transactionnelle JPA |

## Déploiement

1. Compiler le projet : `mvn clean package`
2. Configurer PostgreSQL et créer la base de données
3. Configurer la datasource dans `server.xml`
4. Déployer le WAR sur Liberty
5. Tester avec les endpoints ci-dessus

## Troubleshooting

### Erreur de connexion à la base de données
- Vérifier que PostgreSQL est démarré
- Vérifier les credentials dans `server.xml`
- Vérifier que le driver PostgreSQL est présent

### Erreur JPA
- Vérifier que la feature `jpa-3.1` est activée
- Vérifier le fichier `persistence.xml`
- Consulter les logs Liberty pour plus de détails

### Erreur 404
- Vérifier que l'application est déployée
- Vérifier le context root (par défaut `/demo`)
- Vérifier l'URL complète : `http://localhost:9080/demo/apip/orderp`
