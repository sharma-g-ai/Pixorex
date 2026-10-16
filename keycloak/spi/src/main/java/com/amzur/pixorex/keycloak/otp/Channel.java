package com.amzur.pixorex.keycloak.otp;

public enum Channel {
    SMS("sms"),
    EMAIL("email");

    private final String id;

    Channel(String id) {
        this.id = id;
    }

    public String id() {
        return id;
    }

    public static Channel fromId(String id) {
        for (Channel channel : values()) {
            if (channel.id.equals(id)) {
                return channel;
            }
        }
        return null;
    }
}
