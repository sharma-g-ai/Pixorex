<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true; section>
    <#if section = "header">
        ${msg("pixorexChannelTitle")}
    <#elseif section = "form">
        <form id="px-channel-form" class="px-form" action="${url.loginAction}" method="post">
            <fieldset class="px-choices">
                <legend class="px-sr-only">${msg("pixorexChannelTitle")}</legend>
                <#list pxChannels as option>
                    <label class="px-choice">
                        <input type="radio" name="channel" value="${option.id}" <#if option?is_first>checked</#if>>
                        <span class="px-choice-text">
                            <#if option.id == "sms">${msg("pixorexChannelSms", option.destination)}<#else>${msg("pixorexChannelEmail", option.destination)}</#if>
                        </span>
                    </label>
                </#list>
            </fieldset>
            <button class="px-button" type="submit">${msg("pixorexSendCode")}</button>
        </form>
        <a class="px-link" href="${url.loginRestartFlowUrl}">${msg("pixorexStartOver")}</a>
    </#if>
</@layout.registrationLayout>
