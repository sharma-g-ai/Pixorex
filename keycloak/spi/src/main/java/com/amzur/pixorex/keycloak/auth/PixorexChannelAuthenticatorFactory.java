package com.amzur.pixorex.keycloak.auth;

import java.util.List;

import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;
import org.keycloak.provider.ProviderConfigProperty;

public class PixorexChannelAuthenticatorFactory extends AbstractPixorexAuthenticatorFactory {

    public static final String PROVIDER_ID = "pixorex-channel";
    public static final String SMS_CLIENTS = "smsClients";
    public static final String DEFAULT_SMS_CLIENTS = "pixorex-mobile";

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayType() {
        return "Pixorex Channel";
    }

    @Override
    public String getHelpText() {
        return "Chooses SMS or email for the code. Web: email only. Mobile: SMS or email, or SMS only for an invited technician. Skips the screen when only one channel applies.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of(stringProperty(SMS_CLIENTS, "Clients that may use SMS",
                "Comma-separated client ids that may send codes by SMS. Every other client uses email only.", DEFAULT_SMS_CLIENTS));
    }

    @Override
    public Authenticator create(KeycloakSession session) {
        return new PixorexChannelAuthenticator();
    }
}
