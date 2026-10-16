package com.amzur.pixorex.keycloak.auth;

import java.util.List;

import org.keycloak.Config;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.models.AuthenticationExecutionModel.Requirement;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;

abstract class AbstractPixorexAuthenticatorFactory implements AuthenticatorFactory {

    private static final Requirement[] REQUIREMENT_CHOICES = { Requirement.REQUIRED, Requirement.DISABLED };

    @Override
    public String getReferenceCategory() {
        return null;
    }

    @Override
    public boolean isConfigurable() {
        return !getConfigProperties().isEmpty();
    }

    @Override
    public Requirement[] getRequirementChoices() {
        return REQUIREMENT_CHOICES;
    }

    @Override
    public boolean isUserSetupAllowed() {
        return false;
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of();
    }

    @Override
    public void init(Config.Scope config) {
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
    }

    @Override
    public void close() {
    }

    static ProviderConfigProperty stringProperty(String name, String label, String help, String defaultValue) {
        return new ProviderConfigProperty(name, label, help, ProviderConfigProperty.STRING_TYPE, defaultValue);
    }
}
