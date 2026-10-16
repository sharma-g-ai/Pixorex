package com.amzur.pixorex.keycloak.sms;

import org.keycloak.Config;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderFactory;

public interface SmsSenderFactory extends ProviderFactory<SmsSender> {

    @Override
    default void init(Config.Scope config) {
    }

    @Override
    default void postInit(KeycloakSessionFactory factory) {
    }

    @Override
    default void close() {
    }
}
