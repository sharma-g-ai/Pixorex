<#-- Pixorex layout for every login page, including Keycloak's own (expired, error). Never shows the internal username. -->
<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html lang="${lang}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <meta name="color-scheme" content="light">
    <title>${msg("pixorexPageTitle")}</title>
    <link rel="icon" href="${url.resourcesPath}/img/favicon.svg" type="image/svg+xml">
    <#if properties.stylesCommon?has_content>
        <#list properties.stylesCommon?split(' ') as style>
            <link href="${url.resourcesCommonPath}/${style}" rel="stylesheet">
        </#list>
    </#if>
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet">
        </#list>
    </#if>
    <#if authenticationSession??>
        <script type="module">
            <#outputformat "JavaScript">
            import { checkAuthSession } from ${(url.resourcesPath + "/js/authChecker.js")?c};
            checkAuthSession(${authenticationSession.authSessionIdHash?c});
            </#outputformat>
        </script>
    </#if>
</head>
<body class="px-body ${bodyClass}" data-page-id="login-${pageId!''}">
<main class="px-shell">
    <section class="px-card" aria-labelledby="px-title">
        <div class="px-brand">
            <span class="px-logo" aria-hidden="true">P</span>
            <span class="px-brand-name">Pixorex</span>
        </div>
        <h1 id="px-title" class="px-title"><#nested "header"></h1>

        <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
            <div class="px-alert px-alert-${message.type}" role="${(message.type == 'error')?then('alert', 'status')}">
                ${kcSanitize(message.summary)?no_esc}
            </div>
        </#if>

        <#nested "form">

        <#if displayInfo>
            <div class="px-info"><#nested "info"></div>
        </#if>
    </section>
    <p class="px-footer">${msg("pixorexFooter")}</p>
</main>
</body>
</html>
</#macro>
