package com.amzur.pixorex.keycloak.email;

import java.util.LinkedHashMap;
import java.util.Map;

import org.keycloak.Config;
import org.keycloak.email.DefaultEmailSenderProvider;
import org.keycloak.email.DefaultEmailSenderProviderFactory;
import org.keycloak.email.EmailSenderProvider;
import org.keycloak.email.EmailSenderProviderFactory;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;

/**
 * Default email sender for Pixorex: real addresses use realm SMTP; {@code *.local} use Mailpit.
 */
public class PixorexRoutingEmailSenderProviderFactory implements EmailSenderProviderFactory {

    public static final String PROVIDER_ID = "pixorex-routing";

    private final DefaultEmailSenderProviderFactory delegateFactory = new DefaultEmailSenderProviderFactory();
    private Map<String, String> localSmtp = mailpitDefaults("mailpit", "1025");

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public int order() {
        // Prefer this over Keycloak's built-in "default" when no explicit provider is selected.
        return 100;
    }

    @Override
    public void init(Config.Scope config) {
        delegateFactory.init(config);
        String host = firstNonBlank(
                config.get("local-host"),
                System.getenv("PIXOREX_LOCAL_SMTP_HOST"),
                "mailpit");
        String port = firstNonBlank(
                config.get("local-port"),
                System.getenv("PIXOREX_LOCAL_SMTP_PORT"),
                "1025");
        String from = firstNonBlank(
                config.get("local-from"),
                System.getenv("PIXOREX_LOCAL_SMTP_FROM"),
                "no-reply@pixorex.local");
        localSmtp = mailpitDefaults(host, port);
        localSmtp.put("from", from);
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
        delegateFactory.postInit(factory);
    }

    @Override
    public EmailSenderProvider create(KeycloakSession session) {
        EmailSenderProvider delegate =
                new DefaultEmailSenderProvider(session, delegateFactory.getEmailAuthenticators());
        return new PixorexRoutingEmailSenderProvider(delegate, localSmtp);
    }

    @Override
    public void close() {
        delegateFactory.close();
    }

    private static Map<String, String> mailpitDefaults(String host, String port) {
        Map<String, String> cfg = new LinkedHashMap<>();
        cfg.put("host", host);
        cfg.put("port", port);
        cfg.put("from", "no-reply@pixorex.local");
        cfg.put("fromDisplayName", "Pixorex");
        cfg.put("auth", "false");
        cfg.put("ssl", "false");
        cfg.put("starttls", "false");
        return cfg;
    }

    private static String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value.trim();
            }
        }
        return "";
    }
}
