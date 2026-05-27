# frozen_string_literal: true
# DSECONDS LED Wall Designer FREE — Extension loader
# Copyright (c) 2025 Dseconds (Vincenzo Torriani). All rights reserved.

require 'sketchup.rb'
require 'extensions.rb'

module DsecondsLEDWallFree
  EXT_NAME = 'DSECONDS LED Wall Designer FREE'.freeze
  EXT_PATH = 'dseconds_led_wall_designer_free/core'.freeze

  unless file_loaded?(__FILE__)
    extension = SketchupExtension.new(EXT_NAME, EXT_PATH)
    extension.description = 'DSECONDS LED Wall Designer FREE — Flat LED wall layout tool. ' \
                            'Upgrade to PRO at dseconds.com for full database (40+ products), ' \
                            'curved walls, unlimited walls, and exports.'
    extension.version     = '1.0.3'
    extension.creator     = 'Dseconds'
    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
