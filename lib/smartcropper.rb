require 'RMagick'
require 'entropy_variance'
require 'byebug'

class SmartCropper
  include Magick

  attr_accessor :image
  attr_accessor :steps

  # Create a new SmartCropper object from a ImageList single image object.
  #  If you want to provide a file by its path use SmartCropper.from_file('/path/to/image.png').
  def initialize(image)
    @image = image

    # Hardcoded (but overridable) defaults.
    @steps  = 100

    # Preprocess image.
    @quantized_image = @image.quantize

    # Prepare some often-used internal variables.
    @rows = @image.rows
    @columns = @image.columns
  end

  # Open create a smartcropper from a file on disk.
  def self.from_file(image_path)
    image = ImageList.new(image_path).last
    return SmartCropper.new(image)
  end

  # Crops an image to width x height
  def smart_crop(width, height)
    sq = square(width, height)
    return @image.crop!(sq[:left], sq[:top], width, height, true)
  end

  def auto_crop(draw_line = false)
    sq = colored_area_detect
    if draw_line
      box = Magick::Draw.new
      box.stroke('tomato')
      box.fill_opacity(0)
      box.stroke_opacity(0.75)
      box.stroke_width(6)
      box.polygon(sq[:left], sq[:top], sq[:right], sq[:top], sq[:right], sq[:bottom], sq[:left], sq[:bottom])
      box.draw(@image)
      @image
    else
      return @image.crop!(sq[:left], sq[:top], sq[:right], sq[:bottom], true)
    end
  end

  # Squares an image (with smart_square) and then scales that to width, heigh
  def smart_crop_and_scale(width, height)
    smart_square
    return @image.scale!(width, height)
  end

  # Squares an image by slicing off the least interesting parts.
  # Usefull for squaring images such as thumbnails. Usefull before scaling.
  def smart_square
    if @rows != @columns #None-square images must be shaved off.
      if @rows < @columns #landscape
        crop_height = crop_width = @rows
      else # portrait
        crop_height = crop_width = @columns
      end

      sq = square(crop_width, crop_height)
      @image.crop!(sq[:left], sq[:top], crop_width, crop_height, true)
    end

    @image
  end

  # Finds the most interesting square with size width x height.
  #
  # Returns a hash {:left => left, :top => top, :right => right, :bottom => bottom}
  def square(width, height)
    return smart_crop_by_trim(width, height)
  end

  private
    # Determines if the image should be cropped.
    # Image should be cropped if original is larger then requested size.
    # In all other cases, it should not.
    def should_crop?
      return (@columns > @width) && (@rows < @height)
    end

    def colored_area_detect
      left, top = 0, 0
      right, bottom = @columns, (@rows-400)
      width, height = right, bottom
      requested_x, requested_y = 200, 200
      step_size = step_size()
      v = {
        :left_side => EntropyVariance.new,
        :right_side => EntropyVariance.new,
        :bottom_side => EntropyVariance.new,
        :top_side => EntropyVariance.new
      }
      # Avoid attempts to slice less then one pixel.
      if step_size > 0
        # Slice from left and right edges until the correct width is reached.
        while (width > requested_x)
          slice_width = [(width - requested_x), step_size].min
          unless v[:left_side].last_elements_abnormally_large?
            v[:left_side] << entropy_slice(@quantized_image, left, 0, slice_width, bottom)
            left += slice_width unless v[:left_side].last_elements_abnormally_large?
          end

          unless v[:right_side].last_elements_abnormally_large?
            v[:right_side] << entropy_slice(@quantized_image, (right - slice_width), 0, slice_width, bottom)
            right -= slice_width unless v[:right_side].last_elements_abnormally_large?
          end
          #byebug
          break if v[:left_side].last_elements_abnormally_large? && v[:right_side].last_elements_abnormally_large?

          width = (right - left)

          puts "width:#{width}:left_side:#{v[:left_side].cur}:right_side:#{v[:right_side].cur}"
        end
        puts "v[:left_side]:#{v[:left_side].elements}"
        puts "v[:right_side]:#{v[:right_side].elements}"

        last_side = 0
        # Slice from top and bottom edges until the correct height is reached.
        while (height > requested_y)
          slice_height = [(height - step_size), step_size].min


          unless v[:bottom_side].last_elements_abnormally_large?
            v[:bottom_side] << entropy_slice(@quantized_image, 0, (bottom - slice_height), @columns, slice_height)
            unless v[:bottom_side].last_elements_abnormally_large?

              bottom -= slice_height
              puts "taking up bottom"
            end
          end

          unless v[:top_side].last_elements_abnormally_large?
            v[:top_side] << entropy_slice(@quantized_image, 0, top, @columns, slice_height)
            unless v[:top_side].last_elements_abnormally_large?
              puts "cutting off top"
              top += slice_height
            end
          end
          #byebug
          break if v[:top_side].last_elements_abnormally_large? && v[:top_side].last_elements_abnormally_large?

          height = (bottom - top)
          puts "height:#{height}last_side:#{last_side}"
        end
        puts "v[:bottom_side]:#{v[:bottom_side].elements}"
        puts "v[:top_side]:#{v[:top_side].elements}"
      end

      square = {:left => left, :top => top, :right => right, :bottom => bottom}
    end

    def smart_crop_by_trim(requested_x, requested_y)
      left, top = 0, 0
      right, bottom = @columns, @rows
      width, height = right, bottom
      step_size = step_size(requested_x, requested_y)
      # Avoid attempts to slice less then one pixel.
      if step_size > 0
        # Slice from left and right edges until the correct width is reached.
        while (width > requested_x)
          slice_width = [(width - requested_x), step_size].min
          left_side  = entropy_slice(@quantized_image, left, 0, slice_width, bottom)
          right_side = entropy_slice(@quantized_image, (right - slice_width), 0, slice_width, bottom)

          #remove the slice with the least entropy
          if left_side < right_side
            left += slice_width
          else
            right -= slice_width
          end

          width = (right - left)
        end

        # Slice from top and bottom edges until the correct height is reached.
        while (height > requested_y)
          slice_height = [(height - step_size), step_size].min
          top_side    = entropy_slice(@quantized_image, 0, top, @columns, slice_height)
          bottom_side = entropy_slice(@quantized_image, 0, (bottom - slice_height), @columns, slice_height)
          #remove the slice with the least entropy
          if top_side * 1.25 < bottom_side
            top += slice_height
          else
            bottom -= slice_height
          end

          height = (bottom - top)
        end
      end

      square = {:left => left, :top => top, :right => right, :bottom => bottom}
    end

    # Compute the entropy of an image slice.
    def entropy_slice(image_data, x, y, width, height)
      slice = image_data.crop(x, y, width, height)
      entropy = entropy(slice)
    end

    def colorfulness_slice(image_data, x, y, width, height)
      slice = image_data.crop(x, y, width, height)
      entropy = colorfulness(slice)
    end

    def entropy(image_slice)
      hist = image_slice.color_histogram
      hist_size = hist.values.inject{|sum,x| sum ? sum + x : x }.to_f

      entropy = 0
      hist.values.each do |h|
        p = h.to_f / hist_size
        entropy += (p * (Math.log(p)/Math.log(2))) if p != 0
      end
      return entropy * -1
    end
    #image_slice.color_histogram.keys.first.to_color
    #{}"#0165019401CF
    def colorfulness(image_slice)
      hist = image_slice.color_histogram

      return hist.values.size
    end

    def step_size(requested_x = 0, requested_y = 0)
      ((([@rows - requested_x, @columns - requested_y].max)/2)/@steps).to_i
    end
end
