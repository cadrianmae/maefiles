-- Scaffold only: proves the plugin loads and renders before any real
-- metric work is attempted.
function update()
  noctalia.setUpdateInterval(2000)
  barWidget.render(ui.row({ gap = 6, align = "center" }, {
    ui.glyph({ name = "cpu", size = 14 }),
    ui.label({ text = "sysmon ok", fontWeight = "bold" }),
  }))
end
