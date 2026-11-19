package com.amzur.pixorex.keycloak.auth;

import java.util.Optional;

import jakarta.ws.rs.core.Response;

import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.protocol.oidc.OIDCLoginProtocol;
import org.keycloak.sessions.AuthenticationSessionModel;

import com.amzur.pixorex.keycloak.otp.Identifiers;

/**
 * First step of the code sign-in: the user's email (web and mobile; phone sign-in was removed on 19 Nov 2026). An unknown, ambiguous or disabled identifier continues as a "ghost": the following
 * screens look the same, but no user is set and nothing is ever sent (no account enumeration, REQ-01.02).
 */
public class PixorexIdentifierAuthenticator implements Authenticator {

    static final String TEMPLATE = "pixorex-identifier.ftl";
    static final String FIELD = "identifier";

    @Override
    public void authenticate(AuthenticationFlowContext context) {
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        String hint = authSession.getClientNote(OIDCLoginProtocol.LOGIN_HINT_PARAM);
        if (hint != null && !hint.isBlank()) {
            // Consumed once: "start over" must show the empty form instead of looping on the same hint.
            authSession.removeClientNote(OIDCLoginProtocol.LOGIN_HINT_PARAM);
            Optional<String> email = Identifiers.email(hint);
            if (email.isPresent()) {
                resolve(context, email.get());
                return;
            }
        }
        context.challenge(form(context, null, null));
    }

    @Override
    public void action(AuthenticationFlowContext context) {
        String raw = context.getHttpRequest().getDecodedFormParameters().getFirst(FIELD);
        Optional<String> email = Identifiers.email(raw);
        if (email.isEmpty()) {
            context.challenge(form(context, raw, "pixorexIdentifierInvalidEmail"));
            return;
        }
        resolve(context, email.get());
    }

    private void resolve(AuthenticationFlowContext context, String email) {
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        AuthNotes.clearAll(authSession);
        authSession.setAuthNote(AuthNotes.IDENTIFIER, email);

        UserModel user = context.getSession().users().getUserByEmail(context.getRealm(), email);
        if (user == null || !user.isEnabled()) {
            authSession.setAuthNote(AuthNotes.GHOST, "true");
            context.clearUser();
            context.success();
            return;
        }
        context.setUser(user);
        context.getEvent().user(user);
        context.success();
    }

    private static Response form(AuthenticationFlowContext context, String value, String error) {
        var form = context.form()
                .setAttribute("pxIdentifier", value == null ? "" : value);
        if (error != null) {
            form.setError(error);
        }
        return form.createForm(TEMPLATE);
    }

    @Override
    public boolean requiresUser() {
        return false;
    }

    @Override
    public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) {
        return true;
    }

    @Override
    public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) {
    }

    @Override
    public void close() {
    }
}
