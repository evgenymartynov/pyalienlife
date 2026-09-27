-- PyAL currently has no settings (lie it does now >:3)
data:extend{
  {
    type = "bool-setting",
    name = "enable-cranes",
    setting_type = "startup",
    default_value = false
  },
  {
    type = "bool-setting",
    name = "py-caravan-return-camera",
    setting_type = "runtime-per-user",
    default_value = true
  },
  {
    type = "bool-setting",
    name = "py-custom-recipe-gui",
    setting_type = "runtime-per-user",
    default_value = true
  },
  {
    type = "int-setting",
    name = "py-caravan-wait-alert-seconds",
    setting_type = "runtime-global",
    default_value = 600,
    minimum_value = 0
  }
}
