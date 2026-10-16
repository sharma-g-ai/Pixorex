package com.amzur.pixorex.keycloak.events;

import java.time.Duration;

import org.jboss.logging.Logger;
import org.keycloak.Config;
import org.keycloak.events.EventListenerProvider;
import org.keycloak.events.EventListenerProviderFactory;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

/**
 * Listener {@code pixorex-audit}. Configured with {@code KC_SPI_EVENTS_LISTENER__PIXOREX_AUDIT__ENDPOINT} and
 * {@code __SECRET} (from Vault outside local), plus optional {@code __MAX_ATTEMPTS}, {@code __MAX_QUEUED},
 * {@code __TIMEOUT_MILLIS}. Without an endpoint it stays registered but forwards nothing.
 */
public class AuditEventListenerProviderFactory implements EventListenerProviderFactory {

    public static final String PROVIDER_ID = "pixorex-audit";

    private static final Logger LOG = Logger.getLogger(AuditEventListenerProviderFactory.class);

    private AuditDelivery delivery;

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public void init(Config.Scope config) {
        String endpoint = config.get("endpoint");
        String secret = config.get("secret");
        if (endpoint == null || endpoint.isBlank() || secret == null || secret.isBlank()) {
            LOG.warn("pixorex-audit has no endpoint or secret configured; audit events will not be forwarded");
            return;
        }
        delivery = new AuditDelivery(endpoint, secret,
                config.getInt("max-attempts", 3),
                config.getInt("max-queued", 1000),
                Duration.ofMillis(config.getInt("timeout-millis", 3000)));
    }

    @Override
    public EventListenerProvider create(KeycloakSession session) {
        return new AuditEventListenerProvider(session, delivery);
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
    }

    @Override
    public void close() {
        if (delivery != null) {
            delivery.shutdown();
        }
    }
}
