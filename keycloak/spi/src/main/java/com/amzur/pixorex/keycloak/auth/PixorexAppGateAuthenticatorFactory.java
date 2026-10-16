package com.amzur.pixorex.keycloak.auth;

import java.util.List;

import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;

public class PixorexAppGateAuthenticatorFactory extends AbstractPixorexAuthenticatorFactory {

    public static final String PROVIDER_ID = "pixorex-app-gate";
    public static final String CLIENT_ROLES = "clientRoles";
    public static final String DEFAULT_CLIENT_ROLES = "pixorex-web=pixorex-web,pixorex-mobile=pixorex-mobile";

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayType() {
        return "Pixorex App Gate";
    }

    @Override
    public String getHelpText() {
        return "Lets a user into a client only if they hold the realm role mapped to it (technicians never reach the web dashboard). Runs before any code is sent, and again after a cookie sign-in.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of(stringProperty(CLIENT_ROLES, "Client to required realm role",
                "Comma-separated clientId=realmRole pairs. Clients not listed are refused.", DEFAULT_CLIENT_ROLES));
    }

    @Override
    public Authenticator create(KeycloakSession session) {
        return new PixorexAppGateAuthenticator();
    }
}
