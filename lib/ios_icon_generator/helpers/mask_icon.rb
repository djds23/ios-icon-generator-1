# frozen_string_literal: true

# Copyright (c) 2019 Fueled Digital Media, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'json'
require 'base64'
require 'fileutils'

module IOSIconGenerator
  module Helpers
    ##
    # Mask an icon using the parameters provided.
    #
    # The mask is for now always generated in the bottom left corner of the image.
    #
    # @param [String, #read] appiconset_path The path of the original app icon set to use to generate the new one.
    # @param [String, #read] output_folder The folder to create the new app icon set in.
    # @param [Hash<String, Object>, #read] mask A hash representing parameters for creating the mask.
    #        The Hash may contain the following values:
    #        - +background_color+: The background color to use when generating the mask
    #        - +stroke_color+: The stroke color to use when generating the mask. Used for the outline of the mask.
    #        - +stroke_width_offset+: The stroke width of the mask, offset to the image's minimum dimension (width or height).
    #          1.0 means the stroke will have the full width/height of the image
    #        - +suffix+: The suffix to use when generating the new mask
    #        - +file+: The file to use when generating the new mask. This file should be an image, and it will be overlayed over the background.
    #        - +symbol+: The symbol to use when generating the new mask
    #        - +symbol_color+: The color to use for the symbol
    #        - +font+: The font to use for the symbol
    #        - +x_size_ratio+: The size ratio (of the width of the image) to use when generating the mask. 1.0 means the full width, 0.5 means half-width.
    #        - +y_size_ratio+: The size ratio (of the height of the image) to use when generating the mask. 1.0 means the full height, 0.5 means half-height.
    #        - +size_offset+: The size ratio (of the width and height) to use when generating the symbol or file. 1.0 means the full width and height, 0.5 means half-width and half-height.
    #        - +x_offset+: The X offset (of the width of the image) to use when generating the symbol or file. 1.0 means the full width, 0.5 means half-width.
    #        - +y_offset+: The Y offset (of the width of the image) to use when generating the symbol or file. 1.0 means the full height, 0.5 means half-height.
    #        - +shape+: The shape to use when generating the mask. Can be either +:triangle+ or +:square+.
    # @param [Symbol, #read] parallel_processes The number of processes to use when generating the icons.
    #        +nil+ means it'll use as many processes as they are cores on the machine.
    #        +0+ will disables spawning any processes.
    # @param [Lambda(progress [Int], total [Int]), #read] progress An optional progress block called when progress has been made generating the icons.
    #        It should take two parameters:
    #        - +progress+: An integer indicating the current progress out of +total+
    #        - +total+: An integer indicating the total progress
    #
    # @return [String] Return the path to the generated app icon set.
    def self.mask_icon(
      appiconset_path:,
      output_folder:,
      mask: {
        background_color: '#FFFFFF',
        stroke_color: '#000000',
        stroke_width_offset: 0.1,
        suffix: 'Beta',
        symbol: 'b',
        symbol_color: '#7F0000',
        font: 'Helvetica',
        x_size_ratio: 0.54,
        y_size_ratio: 0.54,
        size_offset: 0.0,
        x_offset: 0.0,
        y_offset: 0.0,
        shape: 'triangle',
      },
      parallel_processes: nil,
      progress: nil
    )
      extension = File.extname(appiconset_path)
      output_folder = File.join(output_folder, "#{File.basename(appiconset_path, extension)}-#{mask[:suffix]}#{extension}")

      FileUtils.mkdir_p(output_folder)

      contents_path = File.join(appiconset_path, 'Contents.json')
      raise "Contents.json file not found in #{appiconset_path}" unless File.exist?(contents_path)

      json_content = JSON.parse(File.read(contents_path))
      progress&.call(nil, json_content['images'].count)
      Parallel.each(
        json_content['images'],
        in_processes: parallel_processes,
        finish: lambda do |_item, i, result|
          json_content['images'][i]['filename'] = result
          progress&.call(i, json_content['images'].count)
        end
      ) do |image|
        width, height = /(\d+(?:\.\d)?)x(\d+(?:\.\d)?)/.match(image['size'])&.captures
        scale, = /(\d+(?:\.\d)?)x/.match(image['scale'])&.captures
        raise "Invalid size parameter in Contents.json: #{image['size']}" if width.nil? || height.nil? || scale.nil?

        scale = scale.to_f
        width = width.to_f * scale
        height = height.to_f * scale

        mask_size_width = width * mask[:x_size_ratio].to_f
        mask_size_height = height * mask[:y_size_ratio].to_f

        extension = File.extname(image['filename'])
        icon_output = "#{File.basename(image['filename'], extension)}-#{mask[:suffix]}#{extension}"
        icon_output_path = File.join(output_folder, icon_output)

        draw_shape_parameters = "-strokewidth '#{(mask[:stroke_width_offset] || 0) * [width, height].min}' \
          -stroke '#{mask[:stroke_width_offset].zero? ? 'none' : (mask[:stroke_color] || '#000000')}' \
          -fill '#{mask[:background_color] || '#FFFFFF'}'"
        draw_shape =
          case mask[:shape]
          when :triangle
            "-draw \"polyline -#{width},#{height - mask_size_height} 0,#{height - mask_size_height} #{mask_size_width},#{height} #{mask_size_width},#{height * 2.0} -#{width},#{height * 2.0}\""
          when :square
            "-draw \"rectangle -#{width},#{height * 2.0} #{mask_size_height},#{width - mask_size_width}\""
          else
            raise "Unknown mask shape: #{mask[:shape]}"
          end

        draw_symbol =
          if mask[:file]
            "\\( -background none \
              -density 1536 \
              -resize #{width * mask[:size_offset]}x#{height} \
              \"#{mask[:file]}\" \
              -geometry +#{width * mask[:x_offset]}+#{height * mask[:y_offset]} \\) \
              -gravity southwest \
              -composite"
          else
            "-strokewidth 0 \
              -stroke none \
              -fill '#{mask[:symbol_color] || '#7F0000'}' \
              -font '#{mask[:font]}' \
              -pointsize #{height * mask[:size_offset] * 2.0} \
              -annotate +#{width * mask[:x_offset]}+#{height - height * mask[:y_offset]} '#{mask[:symbol]}'"
          end
        system("convert '#{File.join(appiconset_path, image['filename'])}' #{draw_shape_parameters} #{draw_shape} #{draw_symbol} '#{icon_output_path}'")

        next icon_output
      end

      File.write(File.join(output_folder, 'Contents.json'), JSON.pretty_generate(json_content))

      output_folder
    end
  end
end
