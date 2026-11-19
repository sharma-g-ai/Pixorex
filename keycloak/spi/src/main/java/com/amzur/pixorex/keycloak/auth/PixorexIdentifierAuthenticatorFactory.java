package com.amzur.pixorex.keycloak.auth;

import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;

public class PixorexIdentifierAuthenticatorFactory extends AbstractPixorexAuthenticatorFactory {

    public static final String PROVIDER_ID = "pixorex-identifier";

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
        return "Asks for the user's email (web and mobile) and resolves the user without revealing whether the account exists.";
    }

    @Override
    public Authenticator create(KeycloakSession session) {
        return new PixorexIdentifierAuthenticator();
    }
}
