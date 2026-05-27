# frozen_string_literal: true
# DSECONDS LED Wall Designer FREE v1.0.3
# Copyright (c) 2025 Dseconds (Vincenzo Torriani). All rights reserved.
# Free version — flat LED wall only. Upgrade to PRO at dseconds.com
#
# PRO features (not included): curved walls, full database (40+ products),
# unlimited walls, HTML export, selection report.
#
require 'json'
require 'sketchup.rb'
require 'extensions.rb'

module DsecondsLEDWallFree
    EXTENSION_NAME    = 'DSECONDS LED Wall Designer FREE'.freeze
    EXTENSION_VERSION = '1.0.3'.freeze
    EXTENSION_CREATOR = 'Dseconds'.freeze
    ROOT      = File.dirname(__FILE__)
    UI_PATH   = File.join(ROOT, 'ui', 'dialog.html')
    DB_PATH   = File.join(ROOT, 'led_database.json')
    ICON_24   = File.join(ROOT, 'icons', 'icon_24.png')
    ICON_32   = File.join(ROOT, 'icons', 'icon_32.png')
    ATTR_DICT = 'vt_led_wall_toolkit'
    FREE_DICT = 'DsecondsLEDFree'

    # License tier gate. Flip to 'pro' in the PRO build to remove the
    # one-wall-per-file restriction (and any other future gated features).
    LICENSE_TIER = 'free'.freeze

    def self.license_pro?
      LICENSE_TIER == 'pro'
    end

      # ═══════════════════════════════════════════════════════════════════════
      # DIALOG BUILDER
      # ═══════════════════════════════════════════════════════════════════════
      def self.build_dialog
        dialog = UI::HtmlDialog.new(
          dialog_title:    EXTENSION_NAME,
          preferences_key: 'dseconds_led_wall_designer_free_v103',
          scrollable:      true,
          resizable:       true,
          width:  460,
          height: 860,
          style:  UI::HtmlDialog::STYLE_DIALOG
        )
        dialog.set_file(UI_PATH)

        dialog.add_action_callback('create_led_wall') do |_ctx, raw|
          begin
            payload = JSON.parse(raw)

            # Quick payload sanity check before activating the tool
            %w[panel_width_mm panel_height_mm pixel_pitch_mm wall_width_mm wall_height_mm].each do |k|
              raise "#{k.tr('_',' ')} must be greater than zero." if payload[k].to_f <= 0.0
            end

            tool = PlacementTool.new do |origin|
              msg = begin
                if origin.nil?
                  { ok: false, error: 'Placement cancelled.' }
                else
                  self.create_led_wall(payload, origin)
                end
              rescue => e
                puts("[LED Toolkit] create_led_wall error: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
                { ok: false, error: e.message }
              end
              if @dialog && @dialog.visible?
                @dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate(msg)});")
              end
            end
            Sketchup.active_model.select_tool(tool)

            # Initial reply so the dialog clears its watchdog
            placing = { ok: true, action: 'placing', message: 'Click in the viewport to place the wall origin (Esc to cancel)' }
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate(placing)});")
          rescue => e
            puts("[LED Toolkit] create_led_wall error: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate({ ok: false, error: e.message })});")
          end
        end

        dialog.add_action_callback('create_curved_wall') do |_ctx, _raw|
          result = self.create_curved_wall({})
          dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate(result)});")
        end

        dialog.add_action_callback('open_pro_site') do |_ctx, _raw|
          UI.openURL('https://dseconds.com')
        end

        dialog.add_action_callback('toggle_labels') do |_ctx, _raw|
          begin
            result = self.toggle_label_visibility
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate(result)});")
          rescue => e
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate({ ok: false, error: e.message })});")
          end
        end

        dialog.add_action_callback('load_database') do |_ctx, _raw|
          begin
            result = self.load_database
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate(result)});")
          rescue => e
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate({ ok: false, error: e.message })});")
          end
        end

        dialog.add_action_callback('database_model_details') do |_ctx, raw|
          begin
            result = self.database_model_details(JSON.parse(raw))
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate(result)});")
          rescue => e
            dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate({ ok: false, error: e.message })});")
          end
        end

        dialog.add_action_callback('ping') do |_ctx, _raw|
          dialog.execute_script("window.ledToolkit.onRubyResult(#{JSON.generate({ ok: true, message: 'Bridge OK.' })});")
        end

        dialog.set_on_closed { @dialog = nil }
        dialog
      end

      def self.show_dialog
        @dialog = build_dialog if @dialog.nil? || !@dialog.visible?
        @dialog.bring_to_front if @dialog.respond_to?(:bring_to_front)
        @dialog.show
      end

      def self.show_info
        sel = Sketchup.active_model.selection.first
        unless sel.is_a?(Sketchup::Group) && sel.get_attribute(ATTR_DICT, 'is_led_wall')
          UI.messagebox("Select a DSECONDS LED wall group first.")
          return
        end
        a = ATTR_DICT
        d = {
          name:            sel.get_attribute(a,'name') || 'LED Wall',
          panel_width_mm:  sel.get_attribute(a,'panel_width_mm'),
          panel_height_mm: sel.get_attribute(a,'panel_height_mm'),
          pixel_pitch_mm:  sel.get_attribute(a,'pixel_pitch_mm'),
          panels_x:        sel.get_attribute(a,'panels_x'),
          panels_y:        sel.get_attribute(a,'panels_y'),
          panel_count:     sel.get_attribute(a,'panel_count'),
          total_width_mm:  sel.get_attribute(a,'total_width_mm') || sel.get_attribute(a,'wall_width_mm'),
          total_height_mm: sel.get_attribute(a,'total_height_mm') || sel.get_attribute(a,'wall_height_mm'),
          total_pixels_w:  sel.get_attribute(a,'total_pixels_w'),
          total_pixels_h:  sel.get_attribute(a,'total_pixels_h'),
          area_sqm:        sel.get_attribute(a,'area_sqm'),
          curve_length_mm: sel.get_attribute(a,'curve_length_mm'),
          is_curved:       sel.get_attribute(a,'is_curved'),
          database_brand:  sel.get_attribute(a,'database_brand'),
          database_model:  sel.get_attribute(a,'database_model'),
          weight_kg:       sel.get_attribute(a,'weight_kg'),
          max_power_w:     sel.get_attribute(a,'max_power_w'),
          avg_power_w:     sel.get_attribute(a,'avg_power_w'),
          max_concave_deg: sel.get_attribute(a,'max_concave_deg'),
          max_convex_deg:  sel.get_attribute(a,'max_convex_deg'),
        }
        d[:row_bands] = read_bands_or_uniform(sel, 'row', d[:panel_height_mm], d[:panels_y])
        d[:col_bands] = read_bands_or_uniform(sel, 'col', d[:panel_width_mm],  d[:panels_x])
        total_w   = d[:total_width_mm]  || ((d[:panels_x]||0).to_f * (d[:panel_width_mm]||0).to_f).round(1)
        total_h   = d[:total_height_mm] || 0
        area      = d[:area_sqm] || (total_w.to_f * total_h.to_f / 1_000_000.0).round(3)
        pw        = d[:max_power_w].to_f
        amps_1ph  = pw > 0 ? (pw / 230.0).round(2) : nil
        amps_3ph  = pw > 0 ? (pw / (400.0 * Math.sqrt(3))).round(2) : nil
        wall_type = d[:is_curved] ? 'Curved LED Wall' : 'Flat LED Wall'
        date_str  = Time.now.strftime('%d %b %Y')
        has_overlay = has_grid_overlay?(sel)
        saved_grid_name      = sel.get_attribute(ATTR_DICT, 'grid_display_name').to_s
        saved_grid_name_attr = saved_grid_name.gsub('&', '&amp;').gsub('"', '&quot;').gsub('<', '&lt;').gsub('>', '&gt;')
        effective_display_name = saved_grid_name.empty? ? (d[:name] || 'LED Wall').to_s : saved_grid_name
        safe_name = effective_display_name.gsub(/[^\w\-]/,'_')
        safe_name = 'LED_Wall' if safe_name.empty?

        logo_path = File.join(ROOT,'icons','logo.png')
        logo_b64  = File.exist?(logo_path) ? [File.binread(logo_path)].pack('m0') : nil
        logo_tag  = logo_b64 ? "<img src=\"data:image/png;base64,#{logo_b64}\" style=\"height:40px;\" alt=\"DSECONDS\">" : "<span style=\"font-weight:800;color:#F2C300;\">DSECONDS</span>"

        # FREE report: PRO-only Watts/m² calculation stays excluded; 1ph/3ph
        # currents are simple derivations from max_power_w and are included.
        csv_rows = [
          ['Field','Value'],['Wall Name',effective_display_name],['Wall Type',wall_type],
          ['Total Width mm',total_w],['Total Height mm',total_h],
          ['Panel Width mm',d[:panel_width_mm]],['Panel Height mm',d[:panel_height_mm]],
          ['Pixel Pitch mm',d[:pixel_pitch_mm]],['Panels X',d[:panels_x]],['Panels Y',d[:panels_y]],
          ['Total Panels',d[:panel_count]],['Total Pixels W',d[:total_pixels_w]],
          ['Total Pixels H',d[:total_pixels_h]],['Area m2',area],
          ['Database Brand',d[:database_brand]],['Database Model',d[:database_model]],
          ['Weight kg',d[:weight_kg]],['Max Power W',d[:max_power_w]],['Avg Power W',d[:avg_power_w]],
          ['Current 1ph @ 230V', amps_1ph ? "#{amps_1ph} A" : nil],
          ['Current 3ph @ 400V', amps_3ph ? "#{amps_3ph} A/ph" : nil],
          ['Generated',date_str],
        ].select{|_,v| !v.nil?}

        rows_html = csv_rows[1..].map{|k,v| "<tr><td>#{k}</td><td>#{v}</td></tr>"}.join

        print_html = <<~HTML
          <!DOCTYPE html><html><head><meta charset="utf-8"><title>#{effective_display_name} Report</title>
          <style>*{box-sizing:border-box;margin:0;padding:0;}body{font-family:-apple-system,Arial,sans-serif;padding:32px;color:#111;max-width:720px;margin:0 auto;}.header{display:flex;align-items:center;justify-content:space-between;border-bottom:3px solid #F2C300;padding-bottom:16px;margin-bottom:24px;}.header h1{font-size:20px;margin-bottom:4px;}.meta{font-size:11px;color:#888;}.badge{display:inline-block;background:#F2C300;color:#111;border-radius:4px;padding:2px 10px;font-size:11px;font-weight:700;text-transform:uppercase;margin-left:8px;}.logo-block{text-align:right;}.logo-block a{text-decoration:none;}.site{font-size:10px;color:#aaa;margin-top:4px;}table{width:100%;border-collapse:collapse;margin-bottom:24px;}th{background:#22143B;color:#F2C300;text-align:left;padding:8px 12px;font-size:11px;text-transform:uppercase;}td{padding:8px 12px;border-bottom:1px solid #eee;font-size:13px;}td:first-child{color:#666;font-size:12px;width:45%;}td:last-child{font-weight:600;}tr:nth-child(even) td{background:#fafafa;}.footer{display:flex;align-items:center;justify-content:space-between;font-size:11px;color:#aaa;padding-top:16px;border-top:1px solid #eee;}.footer a{color:#A59BEF;text-decoration:none;font-weight:600;}.no-print{margin-bottom:20px;}.btn{display:inline-block;padding:10px 20px;background:#F2C300;color:#111;border:none;border-radius:8px;font-size:13px;font-weight:700;cursor:pointer;margin-right:8px;}@media print{.no-print{display:none!important;}}</style>
          </head><body>
          <div class="no-print"><button class="btn" onclick="window.print()">&#128438; Print / Save as PDF</button></div>
          <div class="header">
            <div><h1>#{effective_display_name}<span class="badge">#{wall_type}</span></h1><div class="meta">DSECONDS LED Wall Designer FREE v1.0.3 &nbsp;|&nbsp; #{date_str}#{d[:database_model] ? " | #{d[:database_brand]} #{d[:database_model]}" : ""}</div></div>
            <div class="logo-block"><a href="https://www.dseconds.com" target="_blank">#{logo_tag}</a><div class="site">www.dseconds.com</div></div>
          </div>
          <table><tr><th>Field</th><th>Value</th></tr>#{rows_html}</table>
          <div class="footer"><span>For approval purposes only &mdash; DSECONDS AV Design Tools</span><a href="https://www.dseconds.com" target="_blank">www.dseconds.com</a></div>
          </body></html>
        HTML

        info_html = <<~HTML
          <!DOCTYPE html><html><head><meta charset="utf-8"><title>LED Wall Info</title>
          <style>:root{--bg:#22143B;--accent:#F2C300;--accent2:#A59BEF;--text:#e8e8f0;--muted:#8888aa;--line:#3d2560;}*{box-sizing:border-box;margin:0;padding:0;}body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;padding:16px;font-size:13px;}.hdr{display:flex;align-items:center;gap:10px;margin-bottom:12px;padding-bottom:10px;border-bottom:1px solid var(--line);}.dot{width:10px;height:10px;border-radius:50%;background:var(--accent);flex-shrink:0;}h1{font-size:13px;color:var(--accent);text-transform:uppercase;letter-spacing:.08em;}.sub{font-size:11px;color:var(--accent2);margin-top:2px;}.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:10px;}.kpi{background:rgba(255,255,255,.04);border:1px solid var(--line);border-radius:10px;padding:10px;}.kpi b{display:block;font-size:10px;color:var(--muted);margin-bottom:3px;text-transform:uppercase;letter-spacing:.05em;}.kpi .v{font-size:16px;font-weight:700;color:var(--accent);}.kpi .u{font-size:10px;color:var(--muted);margin-left:2px;}.sec{border:1px solid var(--line);border-radius:10px;padding:12px;margin-bottom:10px;}.sec h2{font-size:10px;color:var(--accent2);text-transform:uppercase;letter-spacing:.08em;margin-bottom:8px;}.row{display:flex;justify-content:space-between;align-items:center;padding:5px 0;border-bottom:1px solid rgba(255,255,255,.05);}.row:last-child{border-bottom:none;}.lbl{font-size:12px;color:var(--muted);}.val{font-size:12px;font-weight:600;}.badge{display:inline-block;background:rgba(165,155,239,.15);color:var(--accent2);border:1px solid rgba(165,155,239,.3);border-radius:6px;padding:2px 8px;font-size:10px;font-weight:600;}.export-bar{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;margin-bottom:12px;}.btn{display:block;padding:9px 4px;border:none;border-radius:8px;font-size:11px;font-weight:700;cursor:pointer;text-align:center;text-decoration:none;letter-spacing:.02em;}.btn-read{background:var(--accent);color:#111;}.btn-csv{background:rgba(165,155,239,.2);color:var(--accent2);border:1px solid rgba(165,155,239,.3);}.btn-pdf{background:rgba(255,255,255,.06);color:var(--text);border:1px solid var(--line);}.ftr{font-size:10px;color:var(--muted);text-align:center;margin-top:10px;padding-top:10px;border-top:1px solid var(--line);}.ftr a{color:var(--accent2);text-decoration:none;}</style>
          </head><body>
          <div class="export-bar">
            <a class="btn btn-read" href="skp:show_info@{}">&#8635; Read Wall</a>
            <a class="btn btn-csv"  href="#" onclick="goGrid('save_csv');return false;">&#8615; CSV</a>
            <a class="btn btn-pdf"  href="#" onclick="goGrid('save_report');return false;">&#128438; HTML/PDF</a>
          </div>
          <div style="margin-bottom:6px;">
            <input id="grid_name" type="text" value="#{saved_grid_name_attr}" placeholder="Custom display name (optional, falls back to wall name)" style="padding:8px 10px;border-radius:8px;border:1px solid #3d2560;background:rgba(255,255,255,.05);color:#e8e8f0;font-size:11px;font-family:inherit;width:100%;box-sizing:border-box;outline:none;">
          </div>
          <div class="export-bar" style="grid-template-columns:1fr 1fr;">
            <a class="btn btn-csv" href="#" onclick="goGrid('save_grid_png');return false;">&#8862; Save Grid PNG</a>
            <a class="btn btn-pdf" href="#" onclick="goGrid('toggle_grid_overlay');return false;">#{has_overlay ? '&#8863; Remove Grid' : '&#8862; Apply Grid'}</a>
          </div>
          <script>
            function goGrid(action) {
              var el = document.getElementById('grid_name');
              var n = (el && el.value || '').trim();
              window.location = 'skp:' + action + '@' + encodeURIComponent(n);
            }
          </script>
          <div class="hdr"><div class="dot"></div><div><h1>#{effective_display_name}</h1><div class="sub"><span class="badge">#{wall_type}</span>#{d[:database_model] ? " &nbsp;#{d[:database_brand]} #{d[:database_model]}" : ""}</div></div></div>
          <div class="grid">
            <div class="kpi"><b>Wall Size</b><span class="v">#{total_w.to_i}×#{total_h.to_i}</span><span class="u">mm</span></div>
            <div class="kpi"><b>Panels</b><span class="v">#{d[:panel_count]}</span><span class="u">#{d[:panels_x]}×#{d[:panels_y]}</span></div>
            <div class="kpi"><b>Pixel Pitch</b><span class="v">#{d[:pixel_pitch_mm]}</span><span class="u">mm</span></div>
            <div class="kpi"><b>Area</b><span class="v">#{area}</span><span class="u">m²</span></div>
          </div>
          <div class="sec"><h2>Resolution</h2>
            <div class="row"><span class="lbl">Total Pixels</span><span class="val">#{d[:total_pixels_w]} × #{d[:total_pixels_h]} px</span></div>
            <div class="row"><span class="lbl">Aspect Ratio</span><span class="val">#{d[:total_pixels_w].to_f > 0 ? (d[:total_pixels_w].to_f/d[:total_pixels_h].to_f).round(2) : '—'}</span></div>
          </div>
          <div class="sec"><h2>Power &amp; Weight</h2>
            #{d[:weight_kg] ? "<div class=\"row\"><span class=\"lbl\">Total Weight</span><span class=\"val\">#{d[:weight_kg]} kg</span></div>" : ""}
            #{pw > 0 ? "<div class=\"row\"><span class=\"lbl\">Max Power</span><span class=\"val\">#{pw.to_i} W</span></div>" : ""}
            #{amps_1ph ? "<div class=\"row\"><span class=\"lbl\">Current 1ph @ 230V</span><span class=\"val\">#{amps_1ph} A</span></div>" : ""}
            #{amps_3ph ? "<div class=\"row\"><span class=\"lbl\">Current 3ph @ 400V</span><span class=\"val\">#{amps_3ph} A/ph</span></div>" : ""}
          </div>
          #{d[:curve_length_mm] ? "<div class=\"sec\"><h2>Curve Data</h2><div class=\"row\"><span class=\"lbl\">Arc Length</span><span class=\"val\">#{d[:curve_length_mm]} mm</span></div></div>" : ""}
          <div class="ftr">DSECONDS LED Wall Designer FREE v1.0.3 &mdash; <a href="skp:open_site@{}">www.dseconds.com</a></div>
          </body></html>
        HTML

        @_info_data = { csv_rows: csv_rows, print_html: print_html, safe_name: safe_name, d: d, wall_group: sel, effective_display_name: effective_display_name }

        if @d_info && @d_info.visible?
          @d_info.set_html(info_html)
        else
          @d_info = UI::HtmlDialog.new(dialog_title: 'DSECONDS LED Wall Info (FREE)', width: 460, height: 660, resizable: true, preferences_key: "dseconds_info_free_v103")
          @d_info.add_action_callback('show_info')  { |_,_| self.show_info }
          @d_info.add_action_callback('open_site')  { |_,_| UI.openURL('https://www.dseconds.com') }
          @d_info.add_action_callback('save_csv') do |_, raw_param|
            dat = @_info_data; next unless dat
            custom_name = self.decode_custom_name(raw_param)
            self.persist_grid_display_name(dat[:wall_group], custom_name)
            display_name, file_safe = self.resolve_grid_name(custom_name, dat)
            rows = dat[:csv_rows].map { |k, v| k == 'Wall Name' ? [k, display_name] : [k, v] }
            path = UI.savepanel('Save CSV', '', "#{file_safe}_info.csv")
            next unless path
            path = "#{path}.csv" unless path.downcase.end_with?('.csv')
            File.write(path, rows.map { |r| r.join(',') }.join("\n"), encoding: 'UTF-8')
            UI.messagebox("CSV saved:\n#{path}")
          end
          @d_info.add_action_callback('save_report') do |_, raw_param|
            dat = @_info_data; next unless dat
            custom_name = self.decode_custom_name(raw_param)
            self.persist_grid_display_name(dat[:wall_group], custom_name)
            display_name, file_safe = self.resolve_grid_name(custom_name, dat)
            html = dat[:print_html]
            existing = dat[:effective_display_name].to_s
            if !existing.empty? && existing != display_name
              html = html.sub("<title>#{existing} Report</title>", "<title>#{display_name} Report</title>")
              html = html.sub("<h1>#{existing}<span class=\"badge\">", "<h1>#{display_name}<span class=\"badge\">")
              html = html.sub("<tr><td>Wall Name</td><td>#{existing}</td></tr>", "<tr><td>Wall Name</td><td>#{display_name}</td></tr>")
            end
            path = UI.savepanel('Save HTML Report', '', "#{file_safe}_report.html")
            next unless path
            path = "#{path}.html" unless path.downcase.end_with?('.html') || path.downcase.end_with?('.htm')
            File.write(path, html, encoding: 'UTF-8')
            UI.openURL("file:///#{path.gsub('\\','/')}")
          end
          @d_info.add_action_callback('save_grid_png') do |_, raw_param|
            dat = @_info_data; next unless dat
            custom_name = self.decode_custom_name(raw_param)
            self.persist_grid_display_name(dat[:wall_group], custom_name)
            display_name, file_safe = self.resolve_grid_name(custom_name, dat)
            d_for_grid = self.refresh_grid_data(dat, display_name)
            path = UI.savepanel('Save Grid PNG', '', "#{file_safe}_grid.png")
            next unless path
            path = "#{path}.png" unless path.downcase.end_with?('.png')
            self.generate_grid_png_async(d_for_grid, path) do |success, err|
              if success
                UI.openURL("file:///#{path.gsub('\\','/')}")
              else
                UI.messagebox("Could not generate grid PNG:\n#{err}")
              end
            end
          end
          @d_info.add_action_callback('toggle_grid_overlay') do |_, raw_param|
            dat = @_info_data; next unless dat
            wall = dat[:wall_group]
            unless wall && wall.valid? && wall.is_a?(Sketchup::Group)
              UI.messagebox('Wall is no longer available. Re-select it and click Read Wall.')
              next
            end
            if self.has_grid_overlay?(wall)
              begin
                self.remove_grid_overlay(wall)
                Sketchup.active_model.selection.clear
                Sketchup.active_model.selection.add(wall)
                self.show_info
              rescue => e
                UI.messagebox("Grid overlay error:\n#{e.message}")
              end
            else
              custom_name = self.decode_custom_name(raw_param)
              self.persist_grid_display_name(wall, custom_name)
              display_name, file_safe = self.resolve_grid_name(custom_name, dat)
              d_for_grid = self.refresh_grid_data(dat, display_name)
              tmp_path = File.join(ENV['TEMP'] || Dir.pwd, "#{file_safe}_grid_overlay.png")
              self.generate_grid_png_async(d_for_grid, tmp_path) do |success, err|
                if success
                  begin
                    self.apply_grid_overlay(wall, tmp_path)
                    Sketchup.active_model.selection.clear
                    Sketchup.active_model.selection.add(wall)
                    self.show_info
                  rescue => e
                    UI.messagebox("Grid overlay error:\n#{e.message}")
                  end
                else
                  UI.messagebox("Grid generation failed:\n#{err}")
                end
              end
            end
          end
          @d_info.set_html(info_html)
          @d_info.show
        end
      end

      # ═══════════════════════════════════════════════════════════════════════
      # GEOMETRY HELPERS
      # ═══════════════════════════════════════════════════════════════════════
      def self.to_length_mm(value)
        value.to_f.mm
      end

      def self.pixels_from_mm(size_mm, pitch_mm)
        return 0 if pitch_mm.to_f <= 0.0
        size  = size_mm.to_f
        pitch = pitch_mm.to_f
        common_panel_pixels = {
          500.0  => { 0.9=>540, 1.2=>416, 1.5=>320, 1.6=>320, 1.8=>288, 1.9=>264,
                      2.3=>208, 2.5=>200, 2.6=>192, 2.9=>168, 3.9=>128, 4.8=>104 },
          1000.0 => { 0.9=>1080,1.2=>832, 1.5=>640, 1.6=>640, 1.8=>576, 1.9=>528,
                      2.3=>416, 2.5=>400, 2.6=>384, 2.9=>336, 3.9=>256, 4.8=>208 }
        }
        matched_size = common_panel_pixels.keys.find { |n| (size - n).abs <= 1.0 }
        if matched_size
          matched_pitch = common_panel_pixels[matched_size].keys.find { |n| (pitch - n).abs <= 0.06 }
          return common_panel_pixels[matched_size][matched_pitch] if matched_pitch
        end
        (size / pitch).round
      end

      def self.ensure_tag(model, tag_name)
        return model.layers[tag_name] if model.layers.respond_to?(:[]) && model.layers[tag_name]
        model.layers.add(tag_name)
      end

      # ── Placement tool: lets the user click an origin in the viewport with snap ──
      class PlacementTool
        def initialize(&callback)
          @callback = callback
          @ip = Sketchup::InputPoint.new
        end

        def activate
          Sketchup.status_text = 'LED Wall: click origin point (bottom-left of wall) — Esc to cancel'
          Sketchup.active_model.active_view.invalidate
        end

        def deactivate(view)
          view.invalidate
        end

        def resume(_view)
          Sketchup.status_text = 'LED Wall: click origin point — Esc to cancel'
        end

        def onMouseMove(_flags, x, y, view)
          @ip.pick(view, x, y)
          view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
          @ip.pick(view, x, y)
          return unless @ip.valid?
          pt = @ip.position.clone
          Sketchup.active_model.select_tool(nil)
          @callback.call(pt) if @callback
        end

        def onCancel(_reason, _view)
          Sketchup.active_model.select_tool(nil)
          @callback.call(nil) if @callback
        end

        def draw(view)
          return unless @ip.valid?
          @ip.draw(view)
          view.line_width    = 2
          view.drawing_color = Sketchup::Color.new(242, 195, 0)
          s  = view.pixels_to_model(10, @ip.position)
          pt = @ip.position
          view.draw(GL_LINES, [
            pt.offset(X_AXIS,  s), pt.offset(X_AXIS, -s),
            pt.offset(Y_AXIS,  s), pt.offset(Y_AXIS, -s),
            pt.offset(Z_AXIS,  s), pt.offset(Z_AXIS, -s)
          ])
        end

        def getExtents
          Sketchup.active_model.bounds
        end
      end

      # ── Grid Test Pattern (HTML5 canvas-rendered PNG + SketchUp overlay) ───
      # We render the pattern in a hidden HtmlDialog canvas using the system
      # font (Helvetica Neue / Arial) for anti-aliased, professional-looking
      # text — much nicer than a hand-rolled bitmap font. The dialog auto-runs
      # JS, posts back a base64 PNG, and Ruby decodes + writes it to disk.
      def self.build_grid_canvas_html(row_bands_px, col_bands_px, total_w, total_h, name)
        require 'json'
        colors = ['#8C1E1E', '#828214', '#1E821E', '#148282', '#1E1E8C', '#6E1E6E']
        <<~HTML
          <!DOCTYPE html><html><head><meta charset="utf-8">
          <style>html,body{margin:0;padding:0;background:#1f1530;color:#e8e8f0;font-family:-apple-system,Segoe UI,Arial,sans-serif;font-size:11px;}
          .pad{padding:14px;}</style></head>
          <body>
          <div class="pad">Generating grid PNG…</div>
          <canvas id="c" width="#{total_w}" height="#{total_h}" style="display:none;"></canvas>
          <script>
          (function() {
            try {
              const W = #{total_w}, H = #{total_h};
              const ROW_BANDS = #{row_bands_px.to_json};
              const COL_BANDS = #{col_bands_px.to_json};
              const NAME = #{name.to_json};
              const COLORS = #{colors.to_json};

              // Expand bands into per-tile positions ([{y,h}] and [{x,w}])
              const yPos = [];
              let yc = 0;
              for (const b of ROW_BANDS) { for (let i = 0; i < b.count; i++) { yPos.push({y: yc, h: b.px}); yc += b.px; } }
              const xPos = [];
              let xc = 0;
              for (const b of COL_BANDS) { for (let i = 0; i < b.count; i++) { xPos.push({x: xc, w: b.px}); xc += b.px; } }
              const ROWS = yPos.length;
              const COLS = xPos.length;

              const cv  = document.getElementById('c');
              const ctx = cv.getContext('2d');

              for (let r = 0; r < ROWS; r++) {
                for (let c = 0; c < COLS; c++) {
                  ctx.fillStyle = COLORS[(r + c) % COLORS.length];
                  ctx.fillRect(xPos[c].x, yPos[r].y, xPos[c].w, yPos[r].h);
                }
              }

              // Use the smallest tile dimension across all bands to size the per-tile label
              const minTW = Math.min.apply(null, COL_BANDS.map(b => b.px));
              const minTH = Math.min.apply(null, ROW_BANDS.map(b => b.px));
              const tileFs = Math.max(Math.floor(Math.min(minTW, minTH) * 0.16), 10);
              ctx.font         = '700 ' + tileFs + 'px "Helvetica Neue", Arial, sans-serif';
              ctx.fillStyle    = '#fff';
              ctx.strokeStyle  = '#000';
              ctx.lineWidth    = Math.max(Math.floor(tileFs / 8), 1);
              ctx.lineJoin     = 'round';
              ctx.textAlign    = 'left';
              ctx.textBaseline = 'top';
              const pad = Math.max(Math.floor(Math.min(minTW, minTH) * 0.05), 4);
              for (let r = 0; r < ROWS; r++) {
                for (let c = 0; c < COLS; c++) {
                  const t = (c+1) + ',' + (r+1);
                  ctx.strokeText(t, xPos[c].x + pad, yPos[r].y + pad);
                  ctx.fillText  (t, xPos[c].x + pad, yPos[r].y + pad);
                }
              }

              // Center label kept understated (the grid PNG also goes to the
              // media-server and ships to the real LED, so the test pattern itself
              // must dominate — name + resolution is just a discreet identifier).
              const titleFs = Math.max(Math.floor(W * 0.025), 16);
              const subFs   = Math.max(Math.floor(W * 0.018), 12);
              ctx.font         = '500 ' + titleFs + 'px "Helvetica Neue", Arial, sans-serif';
              ctx.fillStyle    = 'rgba(255,255,255,0.85)';
              ctx.strokeStyle  = 'rgba(0,0,0,0.85)';
              ctx.lineWidth    = Math.max(Math.floor(titleFs / 12), 2);
              ctx.lineJoin     = 'round';
              ctx.textAlign    = 'center';
              ctx.textBaseline = 'middle';
              ctx.strokeText(NAME, W/2, H/2 - titleFs * 0.7);
              ctx.fillText  (NAME, W/2, H/2 - titleFs * 0.7);

              ctx.font      = '500 ' + subFs + 'px "Helvetica Neue", Arial, sans-serif';
              ctx.lineWidth = Math.max(Math.floor(subFs / 12), 1);
              const res = W + ' × ' + H;
              ctx.strokeText(res, W/2, H/2 + subFs * 0.7);
              ctx.fillText  (res, W/2, H/2 + subFs * 0.7);

              // FREE watermark — diagonal, semi-transparent, repeated.
              // Painted last so it overlays the test pattern and the center label.
              // Removable only by switching to PRO (which ships a different renderer).
              ctx.save();
              ctx.translate(W/2, H/2);
              ctx.rotate(-Math.PI / 6);  // 30 degrees
              ctx.font = 'bold ' + Math.max(Math.floor(W * 0.06), 24) + 'px "Helvetica Neue", Arial, sans-serif';
              ctx.fillStyle   = 'rgba(255, 255, 255, 0.18)';
              ctx.strokeStyle = 'rgba(0, 0, 0, 0.12)';
              ctx.lineWidth   = 2;
              ctx.textAlign    = 'center';
              ctx.textBaseline = 'middle';
              const wm = 'DSECONDS FREE — dseconds.com';
              const wmStep = Math.max(Math.floor(H * 0.25), 120);
              for (let wy = -H; wy < H; wy += wmStep) {
                ctx.strokeText(wm, 0, wy);
                ctx.fillText  (wm, 0, wy);
              }
              ctx.restore();

              const data = cv.toDataURL('image/png');
              if (window.sketchup && window.sketchup.grid_png_ready) {
                window.sketchup.grid_png_ready(data);
              } else {
                throw new Error('SketchUp bridge unavailable');
              }
            } catch (e) {
              const err = (e && e.message) || String(e);
              if (window.sketchup && window.sketchup.grid_png_error) {
                window.sketchup.grid_png_error(err);
              }
            }
          })();
          </script></body></html>
        HTML
      end

      def self.decode_custom_name(raw_param)
        s = raw_param.to_s
        s = s.gsub('%7B%7D', '').gsub('{}', '')  # ignore the empty-args sentinel
        begin
          require 'cgi'
          s = CGI.unescape(s)
        rescue StandardError
        end
        s.strip
      end

      # Build the d hash passed to generate_grid_png_async, always re-reading
      # bands FRESH from the current wall so a stale @_info_data (populated by
      # an earlier show_info before bands support existed) doesn't fall back to
      # a uniform grid. This is the single point of truth for "what bands does
      # the grid PNG see".
      def self.refresh_grid_data(dat, display_name)
        wall = dat[:wall_group]
        d    = dat[:d].dup
        d[:row_bands]    = read_bands_or_uniform(wall, 'row', d[:panel_height_mm], d[:panels_y])
        d[:col_bands]    = read_bands_or_uniform(wall, 'col', d[:panel_width_mm],  d[:panels_x])
        d[:display_name] = display_name
        d
      end

      # Read row/col bands stored on a wall.
      # Order of fallback:
      #   1. Stored band-arrays attributes (new walls)
      #   2. Reconstruct from actual panel geometry inside the wall (any flat wall)
      #   3. Single uniform band based on the default panel size (last resort)
      def self.read_bands_or_uniform(wall, axis, fallback_size_mm, fallback_count)
        if wall && wall.respond_to?(:get_attribute)
          sizes  = wall.get_attribute(ATTR_DICT, "#{axis}_band_sizes_mm")
          counts = wall.get_attribute(ATTR_DICT, "#{axis}_band_counts")
          if sizes.is_a?(Array) && counts.is_a?(Array) && sizes.size == counts.size && !sizes.empty?
            return sizes.zip(counts).map { |s, c| { size: s.to_f, count: c.to_i } }
          end
        end
        # Geometry fallback (works for flat walls; curved walls have rotated panels)
        is_curved = wall && wall.respond_to?(:get_attribute) && wall.get_attribute(ATTR_DICT, 'is_curved')
        unless is_curved
          row_bands_geom, col_bands_geom = compute_bands_from_geometry(wall)
          if axis == 'row' && row_bands_geom && !row_bands_geom.empty?
            return row_bands_geom
          elsif axis == 'col' && col_bands_geom && !col_bands_geom.empty?
            return col_bands_geom
          end
        end
        [{ size: fallback_size_mm.to_f, count: fallback_count.to_i }]
      end

      # Walks the panels group inside a wall and reconstructs row/col bands by
      # grouping component-instance positions and sizes. Returns [row_bands, col_bands].
      def self.compute_bands_from_geometry(wall)
        return [nil, nil] unless wall && wall.respond_to?(:entities)
        panels_group = wall.entities.grep(Sketchup::Group).find { |g| g.name == 'Panels' }
        return [nil, nil] unless panels_group

        panels = []
        panels_group.entities.grep(Sketchup::ComponentInstance).each do |inst|
          bb = inst.definition.bounds
          pos = inst.transformation.origin
          w_mm = ((bb.max.x - bb.min.x).to_f / 1.mm).round(1)  # X extent = panel width
          h_mm = ((bb.max.z - bb.min.z).to_f / 1.mm).round(1)  # Z extent = panel height (vertical in flat wall)
          x_mm = (pos.x.to_f / 1.mm).round(1)
          z_mm = (pos.z.to_f / 1.mm).round(1)
          panels << [x_mm, z_mm, w_mm, h_mm]
        end
        return [nil, nil] if panels.empty?

        # Rows: bands are bottom-to-top (matches the build order of create_led_wall flat)
        z_to_h = {}
        panels.each { |x, z, _w, h| z_to_h[z] ||= h }
        z_keys_asc = z_to_h.keys.sort
        row_heights = z_keys_asc.map { |z| z_to_h[z] }

        # Cols: left-to-right
        x_to_w = {}
        panels.each { |x, _z, w, _h| x_to_w[x] ||= w }
        x_keys_asc = x_to_w.keys.sort
        col_widths = x_keys_asc.map { |x| x_to_w[x] }

        [compress_to_bands(row_heights), compress_to_bands(col_widths)]
      rescue StandardError
        [nil, nil]
      end

      def self.compress_to_bands(sizes)
        bands = []
        cur_size  = nil
        cur_count = 0
        sizes.each do |s|
          if cur_size && (cur_size - s).abs < 0.5
            cur_count += 1
          else
            bands << { size: cur_size, count: cur_count } if cur_size
            cur_size  = s
            cur_count = 1
          end
        end
        bands << { size: cur_size, count: cur_count } if cur_size
        bands
      end

      # Migrate legacy walls where weight_kg / max_power_w / avg_power_w were
      # saved as PER-PANEL values from the database. Multiplies by the wall's
      # panel count and stores the per-panel value under *_per_panel for
      # reference. Idempotent: skipped if *_per_panel already exists.
      def self.fix_wall_totals(wall)
        return unless wall && wall.respond_to?(:get_attribute) && wall.get_attribute(ATTR_DICT, 'is_led_wall')
        return if wall.get_attribute(ATTR_DICT, 'weight_kg_per_panel')  # already migrated
        panels = wall.get_attribute(ATTR_DICT, 'panels_x').to_i * wall.get_attribute(ATTR_DICT, 'panels_y').to_i
        return if panels <= 0

        # Try to look up missing values from the database (e.g., legacy
        # curved walls that didn't store weight_kg at all).
        brand      = wall.get_attribute(ATTR_DICT, 'database_brand').to_s
        model_name = wall.get_attribute(ATTR_DICT, 'database_model').to_s
        db_product = nil
        if !brand.empty? && !model_name.empty?
          begin
            data = JSON.parse(File.read(DB_PATH))
            db_product = (data['products'] || []).find { |p| p['brand'].to_s == brand && p['model_name'].to_s == model_name }
          rescue StandardError
          end
        end

        Sketchup.active_model.start_operation('Migrate wall totals', true)
        ['weight_kg', 'max_power_w', 'avg_power_w'].each do |k|
          per_panel = wall.get_attribute(ATTR_DICT, k).to_f
          per_panel = db_product[k].to_f if per_panel <= 0 && db_product && db_product[k]
          next if per_panel <= 0
          wall.set_attribute(ATTR_DICT, "#{k}_per_panel", per_panel)
          wall.set_attribute(ATTR_DICT, k, (per_panel * panels).round(1))
        end
        Sketchup.active_model.commit_operation
        true
      rescue StandardError => e
        Sketchup.active_model.abort_operation rescue nil
        raise e
      end

      def self.fix_all_wall_totals
        walls = Sketchup.active_model.entities.grep(Sketchup::Group).select { |g| g.get_attribute(ATTR_DICT, 'is_led_wall') }
        fixed = 0
        walls.each { |w| fixed += 1 if fix_wall_totals(w) }
        fixed
      end

      # Save the typed name as a wall attribute so it survives dialog refreshes
      # (show_info regenerates the HTML — without persistence the input clears).
      def self.persist_grid_display_name(wall, custom_name)
        return unless wall && wall.respond_to?(:valid?) && wall.valid?
        if custom_name.nil? || custom_name.strip.empty?
          wall.delete_attribute(ATTR_DICT, 'grid_display_name') if wall.attribute_dictionaries && wall.attribute_dictionaries[ATTR_DICT]
        else
          wall.set_attribute(ATTR_DICT, 'grid_display_name', custom_name.strip)
        end
      rescue StandardError
        # Non-critical — don't block the operation
      end

      def self.resolve_grid_name(custom_name, dat)
        if custom_name && !custom_name.empty?
          display = custom_name
          file    = custom_name.gsub(/[^\w\-]/, '_')
        else
          display = (dat[:d][:name] || 'LED Wall').to_s
          file    = dat[:safe_name]
        end
        [display, file]
      end

      def self.has_grid_overlay?(wall_group)
        return false unless wall_group && wall_group.valid?
        wall_group.entities.grep(Sketchup::Group).any? do |g|
          g.get_attribute(ATTR_DICT, 'is_grid_overlay')
        end
      end

      def self.remove_grid_overlay(wall_group)
        model = Sketchup.active_model
        model.start_operation('Remove Grid Overlay', true)
        wall_group.entities.grep(Sketchup::Group).each do |g|
          g.erase! if g.get_attribute(ATTR_DICT, 'is_grid_overlay')
        end
        model.commit_operation
      end

      def self.apply_grid_overlay(wall_group, png_path)
        apply_grid_overlay_flat(wall_group, png_path)
      end

      def self.apply_grid_overlay_flat(wall_group, png_path)
        model = Sketchup.active_model
        total_w_mm = wall_group.get_attribute(ATTR_DICT, 'total_width_mm').to_f
        total_h_mm = wall_group.get_attribute(ATTR_DICT, 'total_height_mm').to_f
        raise 'Wall has no width/height attributes.' if total_w_mm <= 0 || total_h_mm <= 0

        model.start_operation('Apply Grid Overlay', true)
        wall_group.entities.grep(Sketchup::Group).each do |g|
          g.erase! if g.get_attribute(ATTR_DICT, 'is_grid_overlay')
        end

        overlay = wall_group.entities.add_group
        overlay.name = 'GridOverlay'
        overlay.set_attribute(ATTR_DICT, 'is_grid_overlay', true)

        w = total_w_mm.mm
        h = total_h_mm.mm
        y_offset = -0.1.mm  # slightly in front of LED panels (audience side, -Y)
        pts = [
          Geom::Point3d.new(0, y_offset, 0),
          Geom::Point3d.new(w, y_offset, 0),
          Geom::Point3d.new(w, y_offset, h),
          Geom::Point3d.new(0, y_offset, h)
        ]
        face = overlay.entities.add_face(pts)
        face.reverse! if face.normal.y > 0

        mat_name = "GridOverlay_#{wall_group.entityID}"
        mat = model.materials[mat_name] || model.materials.add(mat_name)
        mat.texture = png_path
        mat.texture.size = [w, h] if mat.texture
        face.material      = mat
        face.back_material = mat

        model.commit_operation
        overlay
      end

      # For curved walls we can't use a single flat face. Each panel column has
      # its own rotation around the curve, so we build one full-height face per
      # column at the column's transformation, then position the texture so each
      # face shows only its slice of the unrolled grid PNG.
      def self.make_panel_face(entities, width, height, depth)
        points = [
          Geom::Point3d.new(0,     0, 0),
          Geom::Point3d.new(width, 0, 0),
          Geom::Point3d.new(width, 0, height),
          Geom::Point3d.new(0,     0, height)
        ]
        face = entities.add_face(points)
        face.reverse! if face.normal.y > 0
        face.pushpull(-depth)
        face
      end

      def self.fetch_or_create_material(model, name, color_value, alpha = 1.0)
        mat = model.materials[name] || model.materials.add(name)
        mat.color = color_value
        mat.alpha = alpha if mat.respond_to?(:alpha=)
        mat
      end

      def self.assign_materials(model, entities, front_hex, side_hex)
        front = fetch_or_create_material(model, "VT_LED_Front_#{front_hex}", front_hex)
        side  = fetch_or_create_material(model, "VT_LED_Side_#{side_hex}",   side_hex)
        entities.grep(Sketchup::Face).each do |face|
          n = face.normal
          if n.y < -0.5
            # Front face — normal points toward -Y (audience side)
            face.material = front; face.back_material = side
          elsif n.y > 0.5
            # Back face — normal points toward +Y
            face.material = side; face.back_material = front
          else
            # Side faces — lateral
            face.material = side; face.back_material = side
          end
        end
      end

      # Callout label: SketchUp screen-text anchored to a fixed 3-D world point.
      # The text is always readable at any zoom; the leader line gives 3-D context.
      # A small solid flag face makes the anchor visible even when zoomed out.
      # add_callout_label — anchor_point and offset_vector must be in MODEL space
      # (not group-local space). The text entity is always added to model root
      # so it is never subject to any group transform and stays readable at all
      # zoom levels and angles.
      def self.add_callout_label(entities, text, anchor_point, offset_vector)
        model    = Sketchup.active_model
        root     = model.active_entities
        line_mat = fetch_or_create_material(model, 'VT_LED_Label_Line', '#D1A84D')

        # text_pt in MODEL space: anchor_point is already in model space
        # (callers pass world-space coords), offset brings text clear of geometry
        text_pt = anchor_point.offset(offset_vector)

        # Leader line from wall anchor to text (in root so it's always visible)
        ldr = root.add_line(anchor_point, text_pt)
        ldr.material = line_mat if ldr.respond_to?(:material=)

        # SketchUp screen-text at the text position.
        # add_text is always screen-facing and readable at any zoom.
        # We add to ROOT (not to any group) so no transform is applied.
        note = root.add_text(text, text_pt)
        if note.respond_to?(:layer=)
          lt = model.layers['LED_Labels']
          note.layer = lt if lt
        end
        note
      rescue => e
        puts("LED label error: #{e.message}"); nil
      end

      # ═══════════════════════════════════════════════════════════════════════
      # OPTIMISED MIXED-CABINET SOLVER  (v2.41+)
      #
      # Finds the combination of available cabinet sizes that exactly tiles
      # `target_mm` using the MINIMUM total number of panels (maximises use of
      # the largest cabinet format to reduce seams).
      # ═══════════════════════════════════════════════════════════════════════
      def self.solve_mixed_panels(target_mm, available_sizes_mm)
        target = target_mm.to_f
        return { ok: false, error: 'Target dimension must be > 0.' } if target <= 0.0
        sizes = available_sizes_mm.map(&:to_f).uniq.sort.reverse
        return { ok: false, error: 'No cabinet sizes available.' } if sizes.empty?

        best = nil

        enumerate = lambda do |remaining, idx, acc|
          if remaining.abs < 0.0001
            total = acc.sum { |b| b[:count] }
            types = acc.size
            if best.nil? || total < best[:panel_count] ||
               (total == best[:panel_count] && types < best[:panels].size)
              best = { ok: true, panels: acc.map(&:dup),
                       total_mm: target_mm.to_f.round(2),
                       panel_count: total, mixed: acc.size > 1 }
            end
            return
          end
          return if remaining < -0.0001 || idx >= sizes.size
          sz    = sizes[idx]
          max_n = (remaining / sz + 0.0001).floor
          if best
            lower   = [(remaining / sz - 0.0001).ceil, 0].max
            current = acc.sum { |b| b[:count] }
            return if current + lower >= best[:panel_count]
          end
          max_n.downto(0) do |n|
            new_acc = n > 0 ? acc + [{ size: sz, count: n }] : acc
            enumerate.call(remaining - n * sz, idx + 1, new_acc)
          end
        end

        enumerate.call(target, 0, [])
        best.nil? ? { ok: false, error: nil } : best
      end

      # ═══════════════════════════════════════════════════════════════════════
      # WALL SUMMARY (flat layout)
      # ═══════════════════════════════════════════════════════════════════════
      def self.wall_summary(payload)
        panel_width_mm  = payload['panel_width_mm'].to_f
        panel_height_mm = payload['panel_height_mm'].to_f
        pitch_mm        = payload['pixel_pitch_mm'].to_f
        wall_width_mm   = payload['wall_width_mm'].to_f
        wall_height_mm  = payload['wall_height_mm'].to_f

        raise 'Wall width must be greater than zero.'   if wall_width_mm  <= 0.0
        raise 'Wall height must be greater than zero.'  if wall_height_mm <= 0.0
        raise 'Panel width must be greater than zero.'  if panel_width_mm  <= 0.0
        raise 'Panel height must be greater than zero.' if panel_height_mm <= 0.0

        variants        = Array(payload['compatible_cabinet_variants'] || [])
        variant_widths  = variants.map { |v| v.to_s.split('x').first.to_f }.uniq.select { |v| v > 0 }
        variant_heights = variants.map { |v| v.to_s.split('x').last.to_f  }.uniq.select { |v| v > 0 }
        variant_widths  = [panel_width_mm]  if variant_widths.empty?
        variant_heights = [panel_height_mm] if variant_heights.empty?

        ws = solve_mixed_panels(wall_width_mm, variant_widths)
        unless ws[:ok]
          raise "Width #{wall_width_mm.round(2)} mm cannot be tiled with available cabinet widths " \
                "(#{variant_widths.sort.map { |s| "#{s.to_i} mm" }.join(' or ')}). " \
                "Try a multiple of #{variant_widths.sort.map(&:to_i).join(' or ')} mm."
        end

        hs = solve_mixed_panels(wall_height_mm, variant_heights)
        unless hs[:ok]
          raise "Height #{wall_height_mm.round(2)} mm cannot be tiled with available cabinet heights " \
                "(#{variant_heights.sort.map { |s| "#{s.to_i} mm" }.join(' or ')}). " \
                "Try a multiple of #{variant_heights.sort.map(&:to_i).join(' or ')} mm."
        end

        col_bands      = ws[:panels]
        row_bands      = hs[:panels]
        panels_x       = col_bands.sum { |b| b[:count] }
        panels_y       = row_bands.sum { |b| b[:count] }
        total_pixels_w = col_bands.sum { |b| pixels_from_mm(b[:size], pitch_mm) * b[:count] }
        total_pixels_h = row_bands.sum { |b| pixels_from_mm(b[:size], pitch_mm) * b[:count] }

        mixed_notes = []
        mixed_notes << "W: #{col_bands.map { |b| "#{b[:count]}x#{b[:size].to_i}mm" }.join('+')}" if ws[:mixed]
        mixed_notes << "H: #{row_bands.map { |b| "#{b[:count]}x#{b[:size].to_i}mm" }.join('+')}" if hs[:mixed]

        {
          wall_width_mm:   wall_width_mm.round(2),
          wall_height_mm:  wall_height_mm.round(2),
          panels_x:        panels_x,
          panels_y:        panels_y,
          panel_pixels_w:  pixels_from_mm(panel_width_mm,  pitch_mm),
          panel_pixels_h:  pixels_from_mm(panel_height_mm, pitch_mm),
          total_width_mm:  wall_width_mm.round(2),
          total_height_mm: wall_height_mm.round(2),
          total_pixels_w:  total_pixels_w,
          total_pixels_h:  total_pixels_h,
          panel_count:     panels_x * panels_y,
          area_sqm:        ((wall_width_mm * wall_height_mm) / 1_000_000.0).round(3),
          max_power_w:     (payload['max_power_w'].to_f * panels_x * panels_y).round(1),
          avg_power_w:     (payload['avg_power_w'].to_f * panels_x * panels_y).round(1),
          watts_per_sqm_max: panels_x * panels_y > 0 ? ((payload['max_power_w'].to_f * panels_x * panels_y) / [(wall_width_mm * wall_height_mm) / 1_000_000.0, 0.001].max).round(1) : 0.0,
          watts_per_sqm_avg: panels_x * panels_y > 0 ? ((payload['avg_power_w'].to_f * panels_x * panels_y) / [(wall_width_mm * wall_height_mm) / 1_000_000.0, 0.001].max).round(1) : 0.0,
          amps_max:        ((payload['max_power_w'].to_f * panels_x * panels_y) / 230.0).round(2),
          amps_avg:        ((payload['avg_power_w'].to_f * panels_x * panels_y) / 230.0).round(2),
          aspect_ratio:    total_pixels_h > 0 ? format('%.3f', total_pixels_w.to_f / total_pixels_h.to_f) : '—',
          col_bands:       col_bands,
          row_bands:       row_bands,
          mixed_layout:    ws[:mixed] || hs[:mixed],
          mixed_note:      mixed_notes.join(' | ')
        }
      end

      # ═══════════════════════════════════════════════════════════════════════
      # CURVED WALL — TANGENT-WALKING ENGINE  (v2.42)
      #
      # Algorithm:
      #   1. Read the selected edge/arc from the model. SketchUp stores arcs
      #      and splines as sequences of straight edges sharing vertices, so
      #      we collect all connected co-planar edges as an ordered polyline.
      #   2. Walk along the polyline from the start vertex:
      #      a. At the current position, compute the local tangent direction
      #         from the polyline segment under the cursor.
      #      b. Place a panel whose LEFT edge aligns with the current position,
      #         oriented so its face normal is perpendicular to the tangent
      #         (i.e. the panel FRONT faces the tangent direction — "inward").
      #      c. Advance the cursor to the RIGHT edge of the placed panel
      #         (= current_pos + panel_width along the panel's local X axis).
      #      d. Project that right-edge point onto the polyline to find the
      #         new "foot" on the curve and compute the new tangent there.
      #      e. Compute the hinge angle between consecutive panel normals
      #         (= angle between the two tangent vectors in the XY plane).
      #      f. Snap the hinge angle to the nearest allowed_angle_deg step
      #         defined in the database (convex > 0 / concave < 0).
      #         If the snapped angle exceeds max_concave/max_convex, clamp it.
      #      g. Apply the snapped rotation to the next panel.
      #      h. Stop when the cursor would travel PAST the end of the curve
      #         (truncate — never overshoot).
      #   3. Build one SketchUp group per row of panels (height bands kept
      #      from the mixed-solver), stacked vertically.
      #
      # Coordinate convention (same as flat wall):
      #   X = horizontal width of the wall
      #   Y = depth (into/out of screen) — panels extrude in -Y
      #   Z = vertical height
      #
      # The polyline is assumed to lie in the XY plane (or close to it).
      # Vertical curvature is not supported in v2.42.
      # ═══════════════════════════════════════════════════════════════════════

      # ── helpers ─────────────────────────────────────────────────────────────

      # Extract an ordered list of 2-D points (x,y in model units) from the
      # selected edge/arc. SketchUp arcs are stored as a sequence of short
      # straight edges; we collect them by walking the "curve" entity if
      # available, otherwise by following edge connectivity.
      # ── CURVE / EDGE → ordered polyline ─────────────────────────────────────
      # Accepts a single edge OR an array of edges (SU selects all arc edges at
      # once). Handles Sketchup::ArcCurve, Sketchup::Curve, and plain edges.
      # Returns an Array of Geom::Point3d ordered from one open end to the other.
      # ─────────────────────────────────────────────────────────────────────────
      def self.load_database
        data     = JSON.parse(File.read(DB_PATH))
        products = data['products'] || []
        { ok: true, action: 'database_loaded',
          message: "Database loaded: #{products.length} entries.", database: data }
      end

      def self.database_model_details(payload)
        brand      = payload['brand'].to_s
        model_name = payload['model_name'].to_s
        data       = JSON.parse(File.read(DB_PATH))
        product    = (data['products'] || []).find { |p|
          p['brand'].to_s == brand && p['model_name'].to_s == model_name
        }
        raise 'Database model not found.' unless product
        if product['free_locked']
          return { ok: false, error: "#{product['model_name']} is a PRO model. Upgrade at dseconds.com to unlock the full database." }
        end
        { ok: true, action: 'database_model_details',
          message: "Database model loaded: #{product['model_name']}", product: product }
      end

      # ═══════════════════════════════════════════════════════════════════════
      # FLAT WALL BUILDER (unchanged from v2.41)
      # ═══════════════════════════════════════════════════════════════════════
      def self.create_led_wall(payload, origin = nil)
        model = Sketchup.active_model

        unless license_pro?
          # FREE: block if either (a) this file has already consumed its slot,
          # or (b) a wall is already physically present (e.g. copy-pasted from
          # another file — that file's slot-flag doesn't travel with the geometry).
          slot_used = model.get_attribute(FREE_DICT, 'wall_ever_created', false)
          wall_present = model.entities.grep(Sketchup::Group).any? do |g|
            g.valid? && g.get_attribute(ATTR_DICT, 'is_led_wall') == true
          end

          if slot_used || wall_present
            return {
              ok: false,
              error: "FREE version allows 1 LED wall per file.\n\n" \
                     "This file already contains a LED wall.\n\n" \
                     "Upgrade to PRO at dseconds.com for unlimited walls."
            }
          end
        end

        panel_width_mm  = payload['panel_width_mm'].to_f
        panel_height_mm = payload['panel_height_mm'].to_f
        pixel_pitch_mm  = payload['pixel_pitch_mm'].to_f
        wall_width_mm   = payload['wall_width_mm'].to_f
        wall_height_mm  = payload['wall_height_mm'].to_f
        panel_depth_mm  = [payload['panel_depth_mm'].to_f, 1.0].max
        gap_mm          = payload['gap_mm'].to_f
        add_labels      = payload['add_labels'] == true
        front_color     = payload['front_color'].to_s.strip
        side_color      = payload['side_color'].to_s.strip
        wall_name       = payload['wall_name'].to_s.strip
        wall_name       = 'LED Wall' if wall_name.empty?

        raise 'Panel width must be greater than zero.'           if panel_width_mm  <= 0.0
        raise 'Panel height must be greater than zero.'          if panel_height_mm <= 0.0
        raise 'Pixel pitch must be greater than zero.'           if pixel_pitch_mm  <= 0.0
        raise 'Requested wall width must be greater than zero.'  if wall_width_mm   <= 0.0
        raise 'Requested wall height must be greater than zero.' if wall_height_mm  <= 0.0

        entities = model.active_entities

        summary  = wall_summary(payload)

        col_bands   = summary[:col_bands]
        row_bands   = summary[:row_bands]
        panel_depth = to_length_mm(panel_depth_mm)
        gap         = to_length_mm(gap_mm)

        model.start_operation("Create #{wall_name}", true)

        # FREE: consume the per-file wall slot. Recorded inside the same
        # operation so it survives undo with the geometry (and a single undo
        # restores both — there's no orphan "slot used" state).
        model.set_attribute(FREE_DICT, 'wall_ever_created', true) unless license_pro?

        root = entities.add_group
        root.name = wall_name
        root.transform!(Geom::Transformation.translation(origin)) if origin
        wall_tag = ensure_tag(model, wall_name)
        root.layer = wall_tag if wall_tag
        root.set_attribute(ATTR_DICT, 'is_led_wall',      true)
        root.set_attribute(ATTR_DICT, 'name',             wall_name)
        root.set_attribute(ATTR_DICT, 'free_watermark',   'DSECONDS FREE — dseconds.com')
        root.set_attribute(ATTR_DICT, 'panel_width_mm',   panel_width_mm)
        root.set_attribute(ATTR_DICT, 'panel_height_mm',  panel_height_mm)
        root.set_attribute(ATTR_DICT, 'pixel_pitch_mm',   pixel_pitch_mm)
        root.set_attribute(ATTR_DICT, 'panel_depth_mm',   panel_depth_mm)
        root.set_attribute(ATTR_DICT, 'wall_width_mm',    wall_width_mm)
        root.set_attribute(ATTR_DICT, 'wall_height_mm',   wall_height_mm)
        root.set_attribute(ATTR_DICT, 'panels_x',         summary[:panels_x])
        root.set_attribute(ATTR_DICT, 'panels_y',         summary[:panels_y])
        root.set_attribute(ATTR_DICT, 'gap_mm',           gap_mm)
        root.set_attribute(ATTR_DICT, 'total_width_mm',   summary[:total_width_mm])
        root.set_attribute(ATTR_DICT, 'total_height_mm',  summary[:total_height_mm])
        root.set_attribute(ATTR_DICT, 'total_pixels_w',   summary[:total_pixels_w])
        root.set_attribute(ATTR_DICT, 'total_pixels_h',   summary[:total_pixels_h])
        root.set_attribute(ATTR_DICT, 'row_band_sizes_mm', row_bands.map { |b| b[:size].to_f })
        root.set_attribute(ATTR_DICT, 'row_band_counts',   row_bands.map { |b| b[:count].to_i })
        root.set_attribute(ATTR_DICT, 'col_band_sizes_mm', col_bands.map { |b| b[:size].to_f })
        root.set_attribute(ATTR_DICT, 'col_band_counts',   col_bands.map { |b| b[:count].to_i })
        root.set_attribute(ATTR_DICT, 'panel_count',      summary[:panel_count])
        root.set_attribute(ATTR_DICT, 'area_sqm',         summary[:area_sqm])
        root.set_attribute(ATTR_DICT, 'mixed_layout',     summary[:mixed_layout])
        root.set_attribute(ATTR_DICT, 'mixed_note',       summary[:mixed_note])
        if payload['database_model']
          root.set_attribute(ATTR_DICT, 'database_brand',     payload['database_brand'])
          root.set_attribute(ATTR_DICT, 'database_series',    payload['database_series'])
          root.set_attribute(ATTR_DICT, 'database_model',     payload['database_model'])
          root.set_attribute(ATTR_DICT, 'curve_supported',    payload['curve_supported'])
          root.set_attribute(ATTR_DICT, 'allowed_angles_deg', Array(payload['allowed_angles_deg']).join(','))
          root.set_attribute(ATTR_DICT, 'angle_step_deg',     payload['angle_step_deg'])
          root.set_attribute(ATTR_DICT, 'max_concave_deg',    payload['max_concave_deg'])
          root.set_attribute(ATTR_DICT, 'max_convex_deg',     payload['max_convex_deg'])
          total_panels_flat = summary[:panel_count].to_i
          root.set_attribute(ATTR_DICT, 'weight_kg_per_panel',   payload['weight_kg'].to_f)
          root.set_attribute(ATTR_DICT, 'weight_kg',             (payload['weight_kg'].to_f   * total_panels_flat).round(1))
          root.set_attribute(ATTR_DICT, 'max_power_w_per_panel', payload['max_power_w'].to_f)
          root.set_attribute(ATTR_DICT, 'max_power_w',           (payload['max_power_w'].to_f * total_panels_flat).round(1))
          root.set_attribute(ATTR_DICT, 'avg_power_w_per_panel', payload['avg_power_w'].to_f)
          root.set_attribute(ATTR_DICT, 'avg_power_w',           (payload['avg_power_w'].to_f * total_panels_flat).round(1))
        end

        panel_tag = ensure_tag(model, 'LED_Panels')
        text_tag  = ensure_tag(model, 'LED_Labels')

        panels_group       = root.entities.add_group
        panels_group.name  = 'Panels'
        panels_group.layer = panel_tag if panel_tag

        defs_cache = {}
        get_def = lambda do |cab_w_mm, cab_h_mm|
          key = "#{cab_w_mm.to_i}x#{cab_h_mm.to_i}_#{pixel_pitch_mm}"
          unless defs_cache[key]
            defn = model.definitions.add("VT_LED_Panel_#{key}")
            make_panel_face(defn.entities,
                            to_length_mm(cab_w_mm),
                            to_length_mm(cab_h_mm),
                            panel_depth)
            assign_materials(model, defn.entities,
                             front_color.empty? ? '#FFFFFF' : front_color,
                             side_color.empty?  ? '#2E2E2E' : side_color)
            defs_cache[key] = defn
          end
          defs_cache[key]
        end

        panel_index = 0
        current_z   = 0.0

        row_bands.each do |rb|
          cab_h_mm = rb[:size]
          cab_h    = to_length_mm(cab_h_mm)
          rb[:count].times do
            current_x = 0.0
            col_bands.each do |cb|
              cab_w_mm = cb[:size]
              cab_w    = to_length_mm(cab_w_mm)
              defn     = get_def.call(cab_w_mm, cab_h_mm)
              cb[:count].times do
                inst = panels_group.entities.add_instance(defn, Geom::Transformation.new)
                inst.transform!(Geom::Transformation.translation([current_x, 0, current_z]))
                panel_index += 1
                inst.name = format('P%04d', panel_index)
                current_x += cab_w + gap
              end
            end
            current_z += cab_h + gap
          end
        end

        if add_labels
          # Origin in model space (defaults to world origin when no placement point was given).
          origin_pt = origin.is_a?(Geom::Point3d) ? origin : Geom::Point3d.new(0, 0, 0)
          labels_group       = root.entities.add_group
          labels_group.name  = 'Labels'
          labels_group.layer = text_tag if text_tag
          anchor        = Geom::Point3d.new(
            origin_pt.x + summary[:total_width_mm].mm,
            origin_pt.y,
            origin_pt.z + summary[:total_height_mm].mm
          )
          offset        = Geom::Vector3d.new(500.mm, 0, 1800.mm)
          mixed_line    = summary[:mixed_layout] ? "\n- Mix: #{summary[:mixed_note]}" : ''
          info = "LED WALL\n#{wall_name}\n" \
                 "- #{summary[:panels_x]} x #{summary[:panels_y]} panels\n" \
                 "- #{summary[:wall_width_mm]} x #{summary[:wall_height_mm]} mm\n" \
                 "- #{summary[:total_pixels_w]} x #{summary[:total_pixels_h]} px\n" \
                 "- P#{pixel_pitch_mm}#{mixed_line}"
          add_callout_label(labels_group.entities, info, anchor, offset)
        end

        model.commit_operation

        msg = "#{wall_name} created."
        msg += " Mixed cabinet layout: #{summary[:mixed_note]}." if summary[:mixed_layout]
        { ok: true, message: msg, summary: summary }
      rescue => e
        model.abort_operation if model && model.respond_to?(:abort_operation)
        { ok: false, error: e.message }
      end

      # ═══════════════════════════════════════════════════════════════════════
      # LABELS / REPORTS
      # ═══════════════════════════════════════════════════════════════════════
      def self.toggle_label_visibility
        model     = Sketchup.active_model
        label_tag = model.layers['LED_Labels']
        raise 'No LED labels found in this model yet.' unless label_tag
        new_state = !label_tag.visible?
        model.start_operation('Toggle LED Labels', true)
        label_tag.visible = new_state
        model.commit_operation
        { ok: true, message: new_state ? 'LED labels are now visible.' : 'LED labels are now hidden.' }
      rescue => e
        model.abort_operation if defined?(model) && model && model.respond_to?(:abort_operation)
        { ok: false, error: e.message }
      end

      def self.reset_toolkit_state
        begin; @dialog.close if @dialog && @dialog.visible?; rescue; end
        @dialog = nil
        { ok: true, message: 'Toolkit state reset. Reopen the dialog.' }
      end

      # ── PRO-only stubs (upgrade at dseconds.com) ──────────────────────────
      def self.create_curved_wall(_payload)
        msg = 'Curved walls require the PRO version. Upgrade at dseconds.com'
        UI.messagebox(msg) rescue nil
        { ok: false, error: msg }
      end

      def self.selection_report
        raise 'Selection report is a PRO feature. Upgrade at dseconds.com'
      end

      # Grid PNG generation: FREE renders the same canvas as PRO with a
      # diagonal 'DSECONDS FREE — dseconds.com' watermark baked into the image
      # by build_grid_canvas_html. The watermark is impossible to remove from
      # FREE exports without unlocking PRO (which ships the unwatermarked
      # renderer).
      def self.generate_grid_png_async(d, output_path, &on_done)
        panels_x = d[:panels_x].to_i
        panels_y = d[:panels_y].to_i
        pitch    = d[:pixel_pitch_mm].to_f
        if panels_x <= 0 || panels_y <= 0 || pitch <= 0
          on_done.call(false, 'Wall has no panel/pixel data — re-create the wall.') if on_done
          return
        end

        # Translate mm-bands to pixel-bands (each band keeps its count of consecutive panels)
        row_bands = d[:row_bands] && !d[:row_bands].empty? ? d[:row_bands] : [{ size: d[:panel_height_mm].to_f, count: panels_y }]
        col_bands = d[:col_bands] && !d[:col_bands].empty? ? d[:col_bands] : [{ size: d[:panel_width_mm].to_f,  count: panels_x }]
        # Reverse rows so image-top corresponds to wall-top.
        # The wall is built bottom-up (row_bands[0] sits at z=0), but image y=0 is at the top —
        # without reversal the image would show the wall mirrored vertically.
        row_bands_px = row_bands.reverse.map { |b| { px: pixels_from_mm(b[:size].to_f, pitch).to_i, count: b[:count].to_i } }
        col_bands_px = col_bands.map { |b| { px: pixels_from_mm(b[:size].to_f, pitch).to_i, count: b[:count].to_i } }

        total_w = col_bands_px.sum { |b| b[:px] * b[:count] }
        total_h = row_bands_px.sum { |b| b[:px] * b[:count] }
        if total_w <= 0 || total_h <= 0
          on_done.call(false, 'Wall pixel resolution computes to zero.') if on_done
          return
        end

        display_name = (d[:display_name] || d[:name] || 'LED Wall').to_s.strip
        display_name = 'LED Wall' if display_name.empty?

        html = build_grid_canvas_html(row_bands_px, col_bands_px, total_w, total_h, display_name)

        dlg = UI::HtmlDialog.new(
          dialog_title:    'Generating Grid…',
          scrollable:      false,
          resizable:       false,
          width:           260,
          height:          80,
          preferences_key: 'dseconds_grid_renderer_free'
        )
        dlg.set_html(html)
        dlg.add_action_callback('grid_png_ready') do |_, base64|
          require 'base64'
          begin
            data = base64.to_s.sub(/^data:image\/png;base64,/, '')
            File.binwrite(output_path, Base64.decode64(data))
            on_done.call(true, nil) if on_done
          rescue => e
            on_done.call(false, e.message) if on_done
          ensure
            begin; dlg.close; rescue StandardError; end
          end
        end
        dlg.add_action_callback('grid_png_error') do |_, msg|
          begin
            on_done.call(false, msg.to_s) if on_done
          ensure
            begin; dlg.close; rescue StandardError; end
          end
        end
        dlg.show
      end

      # ═══════════════════════════════════════════════════════════════════════
      # MENU / TOOLBAR REGISTRATION
      # ═══════════════════════════════════════════════════════════════════════
      unless file_loaded?(__FILE__)
        menu    = UI.menu('Extensions')
        submenu = menu.add_submenu(EXTENSION_NAME)
        submenu.add_item('LED Wall Designer (FREE)') { self.show_dialog }
        submenu.add_item('LED Wall Info (FREE)')     { self.show_info }
        submenu.add_separator
        submenu.add_item('Show / Hide LED Labels')   { self.toggle_label_visibility }
        submenu.add_item('Reset Toolkit State')      { self.reset_toolkit_state }
        submenu.add_separator
        submenu.add_item('Upgrade to PRO at dseconds.com') { UI.openURL('https://dseconds.com') }

        toolbar = UI::Toolbar.new('DSECONDS LED Wall FREE')

        cmd = UI::Command.new('LED Wall Designer (FREE)') { self.show_dialog }
        cmd.small_icon      = ICON_24
        cmd.large_icon      = ICON_32
        cmd.tooltip         = 'DSECONDS LED Wall Designer FREE'
        cmd.status_bar_text = 'Open the DSECONDS LED Wall Designer FREE.'
        toolbar.add_item(cmd)

        icon_info_24 = File.join(ROOT, 'icons', 'icon_info_24.png')
        icon_info_32 = File.join(ROOT, 'icons', 'icon_info_32.png')
        cmd_info = UI::Command.new('LED Wall Info (FREE)') { self.show_info }
        cmd_info.small_icon      = File.exist?(icon_info_24) ? icon_info_24 : ICON_24
        cmd_info.large_icon      = File.exist?(icon_info_32) ? icon_info_32 : ICON_32
        cmd_info.tooltip         = 'DSECONDS LED Wall Info FREE — select a LED wall first'
        cmd_info.status_bar_text = 'Show info for selected LED wall.'
        toolbar.add_item(cmd_info)

        toolbar.restore
        file_loaded(__FILE__)
      end
end
