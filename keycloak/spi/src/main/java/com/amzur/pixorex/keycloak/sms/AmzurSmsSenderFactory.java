package com.amzur.pixorex.keycloak.sms;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import org.jboss.logging.Logger;
import org.keycloak.Config;
import org.keycloak.models.KeycloakSession;

import com.amzur.pixorex.keycloak.otp.Masking;

/**
 * Real SMS gateway (P-3). A generic HTTPS POST so the provider's details stay in configuration:
 * {@code KC_SPI_PIXOREX_SMS__AMZUR__URL}, {@code __AUTH_HEADER}, {@code __AUTH_VALUE}, {@code __SENDER},
 * {@code __FORMAT} (json|form), {@code __BODY_TEMPLATE}, {@code __TIMEOUT_SECONDS}. The auth value comes from Vault
 * in deployed environments and is never logged.
 */
public class AmzurSmsSenderFactory implements SmsSenderFactory {

    public static final String PROVIDER_ID = "amzur";

    private static final Logger LOG = Logger.getLogger(AmzurSmsSenderFactory.class);
    private static final String DEFAULT_BODY = "{\"to\":\"{to}\",\"from\":\"{sender}\",\"text\":\"{text}\"}";

    private String url;
    private String authHeader;
    private String authValue;
    private String sender;
    private String format;
    private String bodyTemplate;
    private Duration timeout;
    private HttpClient client;

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public void init(Config.Scope config) {
        url = value(config, "url", null);
        authHeader = value(config, "auth-header", "Authorization");
        authValue = value(config, "auth-value", null);
        sender = value(config, "sender", "");
        format = value(config, "format", SmsRequestTemplate.JSON);
        bodyTemplate = value(config, "body-template", DEFAULT_BODY);
        timeout = Duration.ofSeconds(Integer.parseInt(value(config, "timeout-seconds", "10")));
        client = HttpClient.newBuilder().connectTimeout(timeout).followRedirects(HttpClient.Redirect.NEVER).build();
    }

    /** Compose passes unset variables as empty strings; treat those as "use the default". */
    private static String value(Config.Scope config, String key, String fallback) {
        String value = config.get(key);
        return value == null || value.isBlank() ? fallback : value.trim();
    }

    @Override
    public SmsSender create(KeycloakSession session) {
        return this::send;
    }

    private void send(String phoneNumber, String message) {
        if (url == null || url.isBlank()) {
            throw new SmsException("pixorex-sms provider 'amzur' has no URL configured (KC_SPI_PIXOREX_SMS__AMZUR__URL)");
        }
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(url))
                .timeout(timeout)
                .header("Content-Type", SmsRequestTemplate.contentType(format))
                .POST(HttpRequest.BodyPublishers.ofString(SmsRequestTemplate.render(bodyTemplate, format, phoneNumber, sender, message)));
        if (authValue != null && !authValue.isBlank()) {
            request.header(authHeader, authValue);
        }
        try {
            HttpResponse<Void> response = client.send(request.build(), HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() / 100 != 2) {
                throw new SmsException("SMS provider returned HTTP " + response.statusCode());
            }
            LOG.debugf("SMS accepted by provider for %s", Masking.phone(phoneNumber));
        } catch (IOException e) {
            throw new SmsException("SMS provider unreachable", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new SmsException("SMS send interrupted", e);
        }
    }
}
