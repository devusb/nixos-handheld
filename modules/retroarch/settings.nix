{
  menu_driver = "rgui";
  rgui_aspect_ratio_lock = "2";
  audio_driver = "alsa";
  input_driver = "udev";
  input_joypad_driver = "udev";
  savestate_auto_load = "true";
  savestate_auto_save = "true";
  rgui_browser_directory = "/roms";

  # Hide menu items
  content_show_contentless_cores = "0";
  content_show_explore = "false";
  content_show_favorites = "false";
  content_show_history = "true";
  content_show_images = "false";
  content_show_music = "false";
  content_show_video = "false";
  content_show_netplay = "false";
  menu_show_quit_retroarch = "true";
  menu_show_shutdown = "true";
  menu_show_reboot = "true";

  # Video — 2x scale fits 640x480 (320x240 core * 2)
  video_scale = "2";

  # Theme
  rgui_menu_color_theme = "20";

  # Input
  input_player1_analog_dpad_mode = "1";

  # Hotkeys
  input_menu_toggle_btn = "nul";
  input_menu_toggle_gamepad_combo = "3";
  input_exit_emulator_btn = "nul";
  menu_swap_ok_cancel_buttons = "false";

  # Volume keys
  input_volume_up = "volumeup";
  input_volume_down = "volumedown";

  # Paths — on roms card so they survive reflash
  system_directory = "/roms/bios";
  savefile_directory = "/roms/saves";
  savestate_directory = "/roms/states";
}
