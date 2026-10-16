package com.amzur.pixorex.keycloak.auth;

import java.util.List;

import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;

public class PixorexIdentifierAuthenticatorFactory extends AbstractPixorexAuthenticatorFactory {

    public static final String PROVIDER_ID = "pixorex-identifier";
    public static final String PHONE_CLIENTS = "phoneClients";
    public static final String DEFAULT_PHONE_CLIENTS = "pixorex-mobile";

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayType() {
        return "Pixorex Identifier";
    }

    @Override
    public String getHelpText() {
        return "Asks for the user's email (web) or email or mobile number (mobile) and resolves the user without revealing whether the account exists.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of(stringProperty(PHONE_CLIENTS, "Clients that accept a mobile number",
                "Comma-separated client ids whose sign-in page accepts an E.164 mobile number as well as an email.", DEFAULT_PHONE_CLIENTS));
    }

    @Override
    public Authenticator create(KeycloakSession session) {
        return new PixorexIdentifierAuthenticator();
    }
}
