<#-- Denied, locked and error pages. The message itself comes from the alert set by the authenticator. -->
<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true; section>
    <#if section = "header">
        ${msg(pxTitle)}
    <#elseif section = "form">
        <a class="px-button px-button-secondary" href="${url.loginRestartFlowUrl}">${msg("pixorexStartOver")}</a>
    </#if>
</@layout.registrationLayout>
