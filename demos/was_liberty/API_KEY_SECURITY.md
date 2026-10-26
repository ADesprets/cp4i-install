# 🔐 API Key Security - Guide d'utilisation

## Vue d'ensemble

L'API Order est maintenant sécurisée par authentification via API Key. Toutes les requêtes (sauf `/health`) nécessitent un header `X-API-Key` valide.

## 🚀 Démarrage rapide

### 1. Tester avec la clé par défaut (développement)

```bash
# GET - Récupérer tous les orders
curl -H "X-API-Key: demo-api-key-change-me-in-production" \
     http://localhost:9080/demo/api/orderp

# POST - Créer un order
curl -X POST \
     -H "X-API-Key: demo-api-key-change-me-in-production" \
     -H "Content-Type: application/json" \
     -d '{"customer":"John Doe","customerid":"123","description":"Test","price":100,"quantity":1,"region":"EMEA"}' \
     http://localhost:9080/demo/api/orderp

# PUT - Mise à jour partielle
curl -X PUT \
     -H "X-API-Key: demo-api-key-change-me-in-production" \
     -H "Content-Type: application/json" \
     -d '{"quantity":5,"price":150}' \
     http://localhost:9080/demo/api/orderp/{orderId}

# DELETE - Supprimer un order
curl -X DELETE \
     -H "X-API-Key: demo-api-key-change-me-in-production" \
     http://localhost:9080/demo/api/orderp/{orderId}
```

### 2. Health Check (pas d'authentification requise)

```bash
curl http://localhost:9080/demo/api/orderp/health
```

## ⚙️ Configuration des API Keys

### Option 1: Fichier de propriétés (Développement)

Éditez `src/main/resources/apikeys.properties`:

```properties
# Plusieurs clés séparées par des virgules
api.keys=dev-key-1,dev-key-2,dev-key-3
```

### Option 2: Variable d'environnement (Recommandé pour Production)

```bash
# Linux/Mac
export API_KEYS="prod-key-abc123,prod-key-xyz789"

# Windows PowerShell
$env:API_KEYS="prod-key-abc123,prod-key-xyz789"

# Docker
docker run -e API_KEYS="prod-key-abc123,prod-key-xyz789" ...

# Kubernetes
apiVersion: v1
kind: Secret
metadata:
  name: api-keys
type: Opaque
stringData:
  API_KEYS: "prod-key-abc123,prod-key-xyz789"
```

### Option 3: System Property (Liberty)

Dans `server.xml`:

```xml
<variable name="API_KEYS" value="prod-key-abc123,prod-key-xyz789"/>
```

Ou via JVM options:

```bash
java -Dapi.keys=prod-key-abc123,prod-key-xyz789 ...
```

## 🔑 Génération de clés sécurisées

### Méthode 1: OpenSSL

```bash
# Générer une clé de 32 caractères
openssl rand -base64 32

# Exemple de sortie:
# 8xK9mP2nQ5rT7vW1yZ3aB4cD6eF8gH0i
```

### Méthode 2: PowerShell

```powershell
# Générer une clé aléatoire
-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | % {[char]$_})
```

### Méthode 3: Python

```python
import secrets
print(secrets.token_urlsafe(32))
```

## 📋 Réponses d'erreur

### 401 Unauthorized - Clé manquante

```json
{
  "error": "API key is required. Please provide a valid API key in the X-API-Key header."
}
```

### 401 Unauthorized - Clé invalide

```json
{
  "error": "Invalid API key. Please check your credentials."
}
```

## 🛡️ Bonnes pratiques de sécurité

### ✅ À FAIRE

1. **Utilisez HTTPS en production**
   ```xml
   <!-- server.xml -->
   <httpEndpoint httpPort="-1" httpsPort="9443" host="*" id="defaultHttpEndpoint"/>
   ```

2. **Générez des clés fortes**
   - Minimum 32 caractères
   - Caractères alphanumériques + symboles
   - Utilisez un générateur cryptographique

3. **Rotation régulière des clés**
   - Changez les clés tous les 90 jours
   - Gardez plusieurs clés actives pendant la transition

4. **Stockage sécurisé**
   - Utilisez des secrets Kubernetes
   - Utilisez des gestionnaires de secrets (HashiCorp Vault, AWS Secrets Manager)
   - Ne commitez JAMAIS les clés dans Git

5. **Monitoring et logging**
   - Loggez les tentatives d'authentification échouées
   - Alertez sur les patterns suspects
   - Auditez l'utilisation des clés

### ❌ À ÉVITER

1. ❌ Ne pas utiliser HTTP en production
2. ❌ Ne pas committer les clés dans le code source
3. ❌ Ne pas utiliser des clés faibles (ex: "password", "123456")
4. ❌ Ne pas partager les clés par email ou chat
5. ❌ Ne pas utiliser la même clé pour tous les environnements

## 🔄 Migration depuis une API non sécurisée

### Étape 1: Déployer avec authentification optionnelle

Modifiez temporairement `ApiKeyFilter.java`:

```java
@Override
public void filter(ContainerRequestContext requestContext) {
    String apiKey = requestContext.getHeaderString(API_KEY_HEADER);
    
    if (apiKey != null && !apiKeyValidator.isValid(apiKey)) {
        // Rejeter seulement si une clé invalide est fournie
        abortWithUnauthorized(requestContext, "Invalid API key");
    }
    // Permettre les requêtes sans clé temporairement
}
```

### Étape 2: Communiquer aux clients

Informez vos clients de la migration et fournissez-leur des clés.

### Étape 3: Activer l'authentification stricte

Revenez au code original qui requiert la clé pour toutes les requêtes.

## 🧪 Tests

### Test unitaire avec JUnit

```java
@Test
public void testApiKeyValidation() {
    ApiKeyValidator validator = new ApiKeyValidator();
    
    // Test avec clé valide
    assertTrue(validator.isValid("demo-api-key-change-me-in-production"));
    
    // Test avec clé invalide
    assertFalse(validator.isValid("invalid-key"));
    
    // Test avec clé null
    assertFalse(validator.isValid(null));
}
```

### Test d'intégration avec REST Assured

```java
@Test
public void testApiWithValidKey() {
    given()
        .header("X-API-Key", "demo-api-key-change-me-in-production")
        .when()
        .get("/api/orderp")
        .then()
        .statusCode(200);
}

@Test
public void testApiWithoutKey() {
    given()
        .when()
        .get("/api/orderp")
        .then()
        .statusCode(401);
}
```

## 📊 Monitoring

### Métriques à surveiller

1. **Taux de requêtes authentifiées vs non authentifiées**
2. **Nombre de tentatives d'authentification échouées**
3. **Utilisation par clé API**
4. **Latence ajoutée par l'authentification**

### Exemple de logging

Les logs incluent automatiquement:

```
INFO: API key validated successfully for path: /api/orderp
WARNING: Invalid API key attempt for path: /api/orderp
WARNING: Missing API key in request to: /api/orderp
```

## 🔧 Dépannage

### Problème: "No API keys configured"

**Solution**: Vérifiez que le fichier `apikeys.properties` existe et contient des clés valides.

### Problème: Les clés ne sont pas chargées

**Solution**: Vérifiez l'ordre de priorité:
1. System property (`-Dapi.keys=...`)
2. Environment variable (`API_KEYS=...`)
3. Properties file (`apikeys.properties`)

### Problème: 401 même avec une clé valide

**Solution**: 
- Vérifiez qu'il n'y a pas d'espaces avant/après la clé
- Vérifiez le nom du header: `X-API-Key` (sensible à la casse)
- Vérifiez les logs Liberty pour voir quelle clé est reçue

## 📞 Support

Pour toute question ou problème:
1. Consultez les logs Liberty: `logs/messages.log`
2. Vérifiez la configuration: `server.xml` et `apikeys.properties`
3. Testez avec curl pour isoler le problème

## 🚀 Prochaines étapes (évolution)

Pour une sécurité renforcée, considérez:

1. **JWT (JSON Web Tokens)** - Tokens avec expiration et claims
2. **OAuth 2.0** - Standard industriel pour l'authentification
3. **Rate Limiting** - Limiter le nombre de requêtes par clé
4. **IP Whitelisting** - Restreindre par adresse IP
5. **Mutual TLS** - Authentification par certificat client

Voir la documentation complète pour plus de détails sur ces options avancées.
