package com.ibm.ad.demo.rest.security;

import jakarta.annotation.Priority;
import jakarta.inject.Inject;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import java.util.logging.Logger;

/**
 * API Key authentication filter for REST endpoints.
 * Validates the X-API-Key header for all incoming requests.
 * 
 * To bypass authentication for specific endpoints, use @PermitAll annotation.
 */
@Provider
@Priority(Priorities.AUTHENTICATION)
public class ApiKeyFilter implements ContainerRequestFilter {

    private static final Logger logger = Logger.getLogger(ApiKeyFilter.class.getName());
    private static final String API_KEY_HEADER = "X-API-Key";
    
    @Inject
    private ApiKeyValidator apiKeyValidator;

    @Override
    public void filter(ContainerRequestContext requestContext) {
        String path = requestContext.getUriInfo().getPath();
        
        // Skip authentication for health check endpoint
        if (path.endsWith("/health")) {
            logger.fine("Skipping API key validation for health check endpoint");
            return;
        }
        
        String apiKey = requestContext.getHeaderString(API_KEY_HEADER);
        
        if (apiKey == null || apiKey.trim().isEmpty()) {
            logger.warning("Missing API key in request to: " + path);
            abortWithUnauthorized(requestContext, "API key is required. Please provide a valid API key in the X-API-Key header.");
            return;
        }
        
        if (!apiKeyValidator.isValid(apiKey)) {
            logger.warning("Invalid API key attempt for path: " + path);
            abortWithUnauthorized(requestContext, "Invalid API key. Please check your credentials.");
            return;
        }
        
        logger.fine("API key validated successfully for path: " + path);
    }
    
    private void abortWithUnauthorized(ContainerRequestContext requestContext, String message) {
        requestContext.abortWith(
            Response.status(Response.Status.UNAUTHORIZED)
                .entity("{\"error\": \"" + message + "\"}")
                .header("Content-Type", "application/json")
                .header("WWW-Authenticate", "API-Key")
                .build()
        );
    }
}
