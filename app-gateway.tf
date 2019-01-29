data "azurerm_key_vault_secret" "cert" {
  name      = "${var.external_cert_name}"
  vault_uri = "${var.external_cert_vault_uri}"
}


data "azurerm_subnet" "ase_subnet" {
  name                 = "core-infra-subnet-0-${var.env}"
  virtual_network_name = "core-infra-vnet-${var.env}"
  resource_group_name  = "core-infra-${var.env}"
}

module "appGw" {
  source            = "git@github.com:hmcts/cnp-module-waf?ref=RDM-3272_make_pbrr_optional"
  env               = "${var.env}"
  subscription      = "${var.subscription}"
  location          = "${var.location}"
  wafName           = "${var.product}-appGW"
  resourcegroupname = "${azurerm_resource_group.rg.name}"
  use_authentication_cert = "true"

  # vNet connections
  gatewayIpConfigurations = [
    {
      name     = "internalNetwork"
      subnetId = "${data.azurerm_subnet.ase_subnet.id}"
    },
  ]

  sslCertificates = [
    {
      name     = "${var.external_cert_name}"
      data     = "${data.azurerm_key_vault_secret.cert.value}"
      password = ""
    },
  ]

  # Http Listeners
  httpListeners = [
    {
      name                    = "${var.product}-http-listener-gateway"
      FrontendIPConfiguration = "appGatewayFrontendIP"
      FrontendPort            = "frontendPort80"
      Protocol                = "Http"
      SslCertificate          = ""
      hostName                = "${var.external_hostname_gateway}"
    },
    {
      name                    = "${var.product}-https-listener-gateway"
      FrontendIPConfiguration = "appGatewayFrontendIP"
      FrontendPort            = "frontendPort443"
      Protocol                = "Https"
      SslCertificate          = "${var.external_cert_name}"
      hostName                = "${var.external_hostname_gateway}"
    },
    {
      name                    = "${var.product}-http-listener-www"
      FrontendIPConfiguration = "appGatewayFrontendIP"
      FrontendPort            = "frontendPort80"
      Protocol                = "Http"
      SslCertificate          = ""
      hostName                = "${var.external_hostname_www}"
    },
    {
      name                    = "${var.product}-https-listener-www"
      FrontendIPConfiguration = "appGatewayFrontendIP"
      FrontendPort            = "frontendPort443"
      Protocol                = "Https"
      SslCertificate          = "${var.external_cert_name}"
      hostName                = "${var.external_hostname_www}"
    },
  ]

  # Backend address Pools
  backendAddressPools = [
    {
      name = "${var.product}-${var.env}-palo-alto"
      backendAddresses = "${module.palo_alto.untrusted_ips_fqdn}"
    },
    {
      name = "${var.product}-${var.env}-backend-pool"
      backendAddresses = [
        {
          ipAddress = "${var.ilbIp}"
        },
      ]
    },
  ]

  backendHttpSettingsCollection = [
    {
      name                           = "backend-80-nocookies-gateway"
      port                           = 80
      Protocol                       = "Http"
      AuthenticationCertificates     = ""
      CookieBasedAffinity            = "Disabled"
      probeEnabled                   = "True"
      probe                          = "http-probe-gateway"
      PickHostNameFromBackendAddress = "False"
      HostName                       = "${var.external_hostname_gateway}"
    },
    {
      name                           = "backend-443-nocookies-gateway"
      port                           = 443
      Protocol                       = "Https"
      AuthenticationCertificates     = "ilbCert"
      CookieBasedAffinity            = "Disabled"
      probeEnabled                   = "True"
      probe                          = "https-probe-gateway"
      PickHostNameFromBackendAddress = "False"
      HostName                       = "${var.external_hostname_gateway}"
    },
    {
      name                           = "backend-80-nocookies-www"
      port                           = 80
      Protocol                       = "Http"
      AuthenticationCertificates     = ""
      CookieBasedAffinity            = "Disabled"
      probeEnabled                   = "True"
      probe                          = "http-probe-www"
      PickHostNameFromBackendAddress = "False"
      HostName                       = "${var.external_hostname_www}"
    },
    {
      name                           = "backend-443-nocookies-www"
      port                           = 443
      Protocol                       = "Https"
      AuthenticationCertificates     = "ilbCert"
      CookieBasedAffinity            = "Disabled"
      probeEnabled                   = "True"
      probe                          = "https-probe-www"
      PickHostNameFromBackendAddress = "False"
      HostName                       = "${var.external_hostname_www}"
    },
  ]

  # Request routing rules
  requestRoutingRules = [
    {
      name                = "http-www"
      ruleType            = "Basic"
      httpListener        = "${var.product}-http-listener-www"
      backendAddressPool  = "${var.product}-${var.env}-backend-pool"
      backendHttpSettings = "backend-80-nocookies-www"
    },
    {
      name                = "https-www"
      ruleType            = "Basic"
      httpListener        = "${var.product}-https-listener-www"
      backendAddressPool  = "${var.product}-${var.env}-backend-pool"
      backendHttpSettings = "backend-443-nocookies-www"
    }
  ]

  urlPathMaps = [
    {
      name                       = "http-url-path-map-gateway"
      defaultBackendAddressPool  = "${var.product}-${var.env}-backend-pool"
      defaultBackendHttpSettings = "backend-80-nocookies-gateway"
      pathRules                  = [
        {
          name                = "http-url-path-map-gateway-rule-palo-alto"
          paths               = ["/documents"]
          backendAddressPool  = "${var.product}-${var.env}-palo-alto"
          backendHttpSettings = "backend-80-nocookies-gateway"
        }
      ]
    },
    {
      name                       = "https-url-path-map-gateway"
      defaultBackendAddressPool  = "${var.product}-${var.env}-backend-pool"
      defaultBackendHttpSettings = "backend-80-nocookies-gateway"
      pathRules                  = [
        {
          name                = "https-url-path-map-gateway-rule-palo-alto"
          paths               = ["/documents"]
          backendAddressPool  = "${var.product}-${var.env}-palo-alto"
          backendHttpSettings = "backend-80-nocookies-gateway"
        }
      ]
    }
  ]

  probes = [
    {
      name                                = "http-probe-gateway"
      protocol                            = "Http"
      path                                = "/"
      interval                            = "${var.health_check_interval}"
      timeout                             = "${var.health_check_timeout}"
      unhealthyThreshold                  = "${var.unhealthy_threshold}"
      pickHostNameFromBackendHttpSettings = "false"
      backendHttpSettings                 = "backend-80-nocookies-gateway"
      host                                = "${var.external_hostname_gateway}"
      healthyStatusCodes                  = "200-404"                  // MS returns 400 on /, allowing more codes in case they change it
    },
    {
      name                                = "https-probe-gateway"
      protocol                            = "Https"
      path                                = "/"
      interval                            = "${var.health_check_interval}"
      timeout                             = "${var.health_check_timeout}"
      unhealthyThreshold                  = "${var.unhealthy_threshold}"
      pickHostNameFromBackendHttpSettings = "false"
      backendHttpSettings                 = "backend-443-nocookies-gateway"
      host                                = "${var.external_hostname_gateway}"
      healthyStatusCodes                  = "200-399"
    },
    {
      name                                = "http-probe-www"
      protocol                            = "Http"
      path                                = "/"
      interval                            = "${var.health_check_interval}"
      timeout                             = "${var.health_check_timeout}"
      unhealthyThreshold                  = "${var.unhealthy_threshold}"
      pickHostNameFromBackendHttpSettings = "false"
      backendHttpSettings                 = "backend-80-nocookies-www"
      host                                = "${var.external_hostname_www}"
      healthyStatusCodes                  = "200-404"                  // MS returns 400 on /, allowing more codes in case they change it
    },
    {
      name                                = "https-probe-www"
      protocol                            = "Https"
      path                                = "/"
      interval                            = "${var.health_check_interval}"
      timeout                             = "${var.health_check_timeout}"
      unhealthyThreshold                  = "${var.unhealthy_threshold}"
      pickHostNameFromBackendHttpSettings = "false"
      backendHttpSettings                 = "backend-443-nocookies-www"
      host                                = "${var.external_hostname_www}"
      healthyStatusCodes                  = "200-399"
    },
  ]
}