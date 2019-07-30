module "appServicePlan" {
  enabled = "${var.env != "sandbox" ? ${var.enable_app_service_plan}:0}"
  source = "git@github.com:hmcts/cnp-module-app-service-plan?ref=RDM-5089"
  location = "${var.location}"
  env = "${var.env}"
  resource_group_name = "${azurerm_resource_group.rg.name}"
  asp_capacity = "${var.asp_capacity}"
  asp_name = "${var.product}"
  ase_name = "${local.ase_name}"
  tag_list = "${local.tags}"
}
