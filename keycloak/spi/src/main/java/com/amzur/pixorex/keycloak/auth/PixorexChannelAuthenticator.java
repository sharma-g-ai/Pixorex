package com.amzur.pixorex.keycloak.auth;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.sessions.AuthenticationSessionModel;

import com.amzur.pixorex.keycloak.otp.Channel;
import com.amzur.pixorex.keycloak.otp.ChannelRules;
import com.amzur.pixorex.keycloak.otp.Identifiers;
import com.amzur.pixorex.keycloak.otp.Masking;

public class PixorexChannelAuthenticator implements Authenticator {

    static final String TEMPLATE = "pixorex-channel.ftl";
    static final String FIELD = "channel";

    @Override
    public void authenticate(AuthenticationFlowContext context) {
        AuthenticationSessionModel authSession = context.getAuthenticationSession();
        boolean smsAllowed = smsAllowed(context);
        UserModel user = context.getUser();

        if (user == null) {
            Identifiers.Type type = parseType(authSession.getAuthNote(AuthNotes.IDENTIFIER_TYPE));
            choose(context, ChannelRules.forUnknownUser(smsAllowed, type));
            return;
        }

        List<Channel> offered = ChannelRules.offered(smsAllowed, user.getFirstAttribute(FlowSupport.PHONE_NUMBER),
                FlowSupport.phoneVerified(user));
        authSession.setAuthNote(AuthNotes.CHANNELS_OFFERED, offered.stream().map(Channel::id).collect(Collectors.joining(",")));
        if (offered.size() == 1) {
            choose(context, offered.get(0));
            return;
        }
        context.challenge(context.form()
                .setAttribute("pxChannels", options(user, offered))
                .createForm(TEMPLATE));
    }

    @Override
    public void action(AuthenticationFlowContext context) {
        Channel choice = Channel.fromId(context.getHttpRequest().getDecodedFormParameters().getFirst(FIELD));
        if (choice == null || !offered(context.getAuthenticationSession()).contains(choice)) {
            authenticate(context);
            return;
        }
        choose(context, choice);
    }

    private static void choose(AuthenticationFlowContext context, Channel channel) {
        context.getAuthenticationSession().setAuthNote(AuthNotes.CHANNEL, channel.id());
        context.success();
    }

    private static List<Map<String, String>> options(UserModel user, List<Channel> offered) {
        List<Map<String, String>> options = new ArrayList<>();
        for (Channel channel : offered) {
            String destination = channel == Channel.SMS ? user.getFirstAttribute(FlowSupport.PHONE_NUMBER) : user.getEmail();
            options.add(Map.of("id", channel.id(), "destination", Masking.destination(channel, destination)));
        }
        return options;
    }

    private static List<Channel> offered(AuthenticationSessionModel authSession) {
        String value = authSession.getAuthNote(AuthNotes.CHANNELS_OFFERED);
        if (value == null) {
            return List.of();
        }
        return Arrays.stream(value.split(",")).map(Channel::fromId).filter(c -> c != null).toList();
    }

    private static boolean smsAllowed(AuthenticationFlowContext context) {
        return FlowSupport.csv(FlowSupport.config(context), PixorexChannelAuthenticatorFactory.SMS_CLIENTS,
                PixorexChannelAuthenticatorFactory.DEFAULT_SMS_CLIENTS).contains(FlowSupport.clientId(context));
    }

    private static Identifiers.Type parseType(String value) {
        return Identifiers.Type.PHONE.name().equals(value) ? Identifiers.Type.PHONE : Identifiers.Type.EMAIL;
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
