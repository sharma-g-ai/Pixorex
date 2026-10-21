package com.amzur.pixorex.keycloak.email;

import java.util.HashMap;
import java.util.Map;

import org.jboss.logging.Logger;
import org.keycloak.email.EmailException;
import org.keycloak.email.EmailSenderProvider;
import org.keycloak.models.UserModel;

/**
 * Sends through the realm SMTP (SendGrid when configured) for real inboxes, and through Mailpit
 * for synthetic {@code *.local} addresses — so demo users keep working without flipping .env.
 */
public class PixorexRoutingEmailSenderProvider implements EmailSenderProvider {

    private static final Logger LOG = Logger.getLogger(PixorexRoutingEmailSenderProvider.class);

    private final EmailSenderProvider delegate;
    private final Map<String, String> localSmtp;

    public PixorexRoutingEmailSenderProvider(EmailSenderProvider delegate, Map<String, String> localSmtp) {
        this.delegate = delegate;
        this.localSmtp = localSmtp;
    }

    @Override
    public void send(Map<String, String> config, UserModel user, String subject, String textBody, String htmlBody)
            throws EmailException {
        String address = user == null ? null : user.getEmail();
        delegate.send(route(config, address), user, subject, textBody, htmlBody);
    }

    @Override
    public void send(Map<String, String> config, String address, String subject, String textBody, String htmlBody)
            throws EmailException {
        delegate.send(route(config, address), address, subject, textBody, htmlBody);
    }

    @Override
    public void validate(Map<String, String> config) throws EmailException {
        delegate.validate(config);
    }

    @Override
    public void close() {
        delegate.close();
    }

    private Map<String, String> route(Map<String, String> realmSmtp, String address) {
        if (!LocalAddresses.isSynthetic(address)) {
            return realmSmtp;
        }
        LOG.debugf("Routing synthetic address %s through local SMTP %s:%s",
                address, localSmtp.get("host"), localSmtp.get("port"));
        Map<String, String> merged = new HashMap<>(localSmtp);
        // Keep display name from the realm when present.
        if (realmSmtp != null && realmSmtp.get("fromDisplayName") != null) {
            merged.put("fromDisplayName", realmSmtp.get("fromDisplayName"));
        }
        return merged;
    }
}
