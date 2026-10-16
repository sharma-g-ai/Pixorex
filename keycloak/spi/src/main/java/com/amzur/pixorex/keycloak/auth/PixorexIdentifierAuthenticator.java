package com.amzur.pixorex.keycloak.auth;

import java.util.List;
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
import com.amzur.pixorex.keycloak.otp.Identifiers.Identifier;

/**
 * First step of the code sign-in. An unknown, ambiguous or disabled identifier continues as a "ghost": the following
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
            Optional<Identifier> identifier = Identifiers.parse(hint, allowPhone(context));
            if (identifier.isPresent()) {
                resolve(context, identifier.get());
                return;
            }
        }
        context.challenge(form(context, null, null));
    }

    @Override
    public void action(AuthenticationFlowContext context) {
        String raw = context.getHttpRequest().getDecodedFormParameters().getFirst(FIELD);
        boolean allowPhone = allowPhone(context);
        Optional<Identifier> identifier = Identifiers.parse(raw, allowPhone);
        if (identifier.isEmpty()) {
            String error = allowPhone ? "pixorexIdentifierInvalidMobile" : "pixorexIdentifierInvalidEmail";
            context.challenge(form(context, raw, error));
            return;
        }
        resolve(context, identifier.get());
    }

    private void resolve(AuthenticationFlowContext context, Identifier identifier) {
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        AuthNotes.clearAll(authSession);
        authSession.setAuthNote(AuthNotes.IDENTIFIER, identifier.value());
        authSession.setAuthNote(AuthNotes.IDENTIFIER_TYPE, identifier.type().name());

        UserModel user = findUser(context.getSession(), context.getRealm(), identifier);
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

    static UserModel findUser(KeycloakSession session, RealmModel realm, Identifier identifier) {
        if (identifier.type() == Identifiers.Type.EMAIL) {
            return session.users().getUserByEmail(realm, identifier.value());
        }
        List<UserModel> holders = session.users()
                .searchForUserByUserAttributeStream(realm, FlowSupport.PHONE_NUMBER, identifier.value())
                .filter(UserModel::isEnabled)
                .toList();
        List<UserModel> verified = holders.stream().filter(FlowSupport::phoneVerified).toList();
        if (verified.size() == 1) {
            return verified.get(0);
        }
        // An invited technician signs in with the pending number; only an unambiguous single holder qualifies.
        return verified.isEmpty() && holders.size() == 1 ? holders.get(0) : null;
    }

    private static boolean allowPhone(AuthenticationFlowContext context) {
        return FlowSupport.csv(FlowSupport.config(context), PixorexIdentifierAuthenticatorFactory.PHONE_CLIENTS,
                PixorexIdentifierAuthenticatorFactory.DEFAULT_PHONE_CLIENTS).contains(FlowSupport.clientId(context));
    }

    private static Response form(AuthenticationFlowContext context, String value, String error) {
        var form = context.form()
                .setAttribute("pxAllowPhone", allowPhone(context))
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
