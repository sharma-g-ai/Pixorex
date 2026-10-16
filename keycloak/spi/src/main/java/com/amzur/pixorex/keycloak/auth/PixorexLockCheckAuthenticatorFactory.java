package com.amzur.pixorex.keycloak.auth;

import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;

public class PixorexLockCheckAuthenticatorFactory extends AbstractPixorexAuthenticatorFactory {

    public static final String PROVIDER_ID = "pixorex-lock-check";

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayType() {
        return "Pixorex Lock Check";
    }

    @Override
    public String getHelpText() {
        return "Shows the locked page with minutes left, and sends nothing, while brute-force detection has the user temporarily disabled.";
    }

    @Override
    public Authenticator create(KeycloakSession session) {
        return new PixorexLockCheckAuthenticator();
    }
}
