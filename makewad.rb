require 'tk'
require 'stringio'
require 'chunky_png'
require 'tty-progressbar'

module MakeWad
  WAD_MAGIC = 'WAD2'
  MIP_TYPE = 'D'
  PALETTE_TYPE = '@'
  NULL_BYTE = [0].pack('C')
  NULL_SHORT = [0].pack('S')
  NULL_LONG = [0].pack('L')

  # A collection of textures whos colors are mapped to a pallete
  class TextureWad
    attr_reader :palette, :textures

    def initialize(palette)
      @palette = palette
      @textures = []
    end

    def add_directory(directory)
      files = Dir.glob("#{directory}/**/*.png")
      files.each { |file| add_file(file) }
    end

    def add_file(file)
      png = ChunkyPNG::Image.from_file(file)
      name = File.basename(file, '.png')
      texture = Texture.new(png.width, png.height, name)
      bar = TTY::ProgressBar.new("Processing #{texture.name.ljust(15)} :bar",
                                 width: 60, total: texture.pixels.length,
                                 bar_format: :block)
      texture_pixels = texture.pixels
      png.pixels.each_with_index do |pixel, idx|
        texture_pixels[idx] = palette.nearest_entry(pixel)
        next unless idx % 500 == 0

        bar.current = idx
      end
      bar.finish
      @textures << texture
    end

    def lump_count
      @textures.length + 1
    end

    def lump_count_long
      [lump_count].pack('l')
    end

    def to_file(filename)
      puts 'Building WAD...'
      File.open(filename, 'wb') do |file|
        file << WAD_MAGIC
        file << lump_count_long
        dir_offset_pos = file.tell
        # Placeholder until we come back to write the actual value
        file << NULL_LONG

        textures.each do |texture|
          texture.offset = file.tell
          file << texture.mipmap
        end

        palette.offset = file.tell
        file << palette.bytes

        dir_offset = file.tell

        textures.each do |texture|
          file << texture.directory_entry
        end

        file << palette.directory_entry

        file.seek(dir_offset_pos)
        file << [dir_offset].pack('l')
      end
    end
  end


   # A texture of 8-bit values corresponding to the index of the TextureWad palette
   class Texture
    attr_accessor :offset
    attr_reader :width, :height, :name, :canvas, :mipmap_size

    def initialize(width, height, name, initial = nil)
      @width = width
      @height = height
      self.name = name
      @canvas = initial || ChunkyPNG::Canvas.new(width, height)
    end

    def pixels
      canvas.pixels
    end

    def name=(new_name)
      if new_name.length > 15
        puts "Warning: \"#{new_name}\" will be truncated to 15 characters."
        new_name = new_name[0...15]
      end
      @name = new_name
    end

    def name_bytes
      bytes = Array.new(16, "\x00")
      name.chars.each_with_index do |char, idx|
        bytes[idx] = char
      end
      bytes.join
    end

    def bytes
      canvas.pixels.pack('C*')
    end

    def width_long
      [width].pack('l')
    end

    def height_long
      [height].pack('l')
    end

    def offset_long
      [offset].pack('l')
    end

    def [](x, y)
      canvas[x, y]
    end

    def []=(x, y, value)
      canvas[x, y] = value
    end

    def scale_down(factor)
      new_width = factor.zero? ? width : (width / (2 * factor))
      new_height = factor.zero? ? height : (height / (2 * factor))
      scaled = canvas.resample_nearest_neighbor(new_width, new_height)
      Texture.new(new_width, new_height, name, scaled)
    end

    def mipmap
      buf = StringIO.new
      buf << name_bytes
      buf << width_long
      buf << height_long

      mips_offset = buf.tell
      # mipmap offset placeholders
      buf << NULL_LONG * 4

      mips = []
      4.times do |i|
        mip = scale_down(i)
        mip.offset = buf.tell
        mips << mip
        buf << mip.bytes
      end

      buf.seek(mips_offset)
      mips.each do |mip|
        buf << mip.offset_long
      end
      @mipmap_size = buf.size
      buf.string
    end

    def mipmap_size_long
      [mipmap_size].pack('l')
    end

    def directory_entry
      buf = StringIO.new
      buf << offset_long
      buf << mipmap_size_long
      buf << mipmap_size_long
      buf << MIP_TYPE
      buf << NULL_BYTE
      buf << NULL_SHORT
      buf << name_bytes
      buf.string
    end
  end


  # A palette of 256 24-bit colors
  class Palette
    attr_accessor :offset
    attr_reader :values

    def self.from_file(filename)
      bytes = File.read(filename).bytes
      values = []
      256.times do
        values << PaletteColor.new(*bytes.shift(3))
      end
      new(values)
    end

    def initialize(values)
      @values = values
      @color_cache = {}
    end

    def nearest_entry(color)
      return 0 if ChunkyPNG::Color.a(color).zero?
      return @color_cache[color] if @color_cache.key?(color)

      best_match = 0
      best_distance = Float::INFINITY
      values.each_with_index do |value, idx|
        distance = ChunkyPNG::Color.euclidean_distance_rgba(color, value.to_i)
        if distance < best_distance
          best_distance = distance
          best_match = idx
        end
      end
      @color_cache[color] = best_match
      best_match
    end

    def bytes
      buf = StringIO.new
      values.each do |value|
        buf << [value.r, value.g, value.b].pack('C*')
      end
      buf.string
    end

    def offset_long
      [offset].pack('l')
    end

    def size_long
      [256 * 3].pack('l')
    end

    def directory_entry
      buf = StringIO.new
      buf << offset_long
      buf << size_long
      buf << size_long
      buf << PALETTE_TYPE
      buf << NULL_BYTE
      buf << NULL_SHORT
      buf << "PALETTE\0\0\0\0\0\0\0\0\0"
      buf.string
    end

     # RGB representation of a pixel
     class PaletteColor
      attr_reader :r, :g, :b, :to_i

      def initialize(red, green, blue)
        @r = red
        @g = green
        @b = blue
        @to_i = ChunkyPNG::Color(r, g, b)
      end
    end
  end

end

# --- GUI Setup ---

root = TkRoot.new do
  title "MakeWad" 
  background '#1e1e1e'
end

defaulttexuredir = "textures"
defaultpalettedir = "palettes/palette.lmp"
defaultoutputdir = "textures.wad"

$texturedir = TkVariable.new(defaulttexuredir)
$palettedir = TkVariable.new(defaultpalettedir)
$outputdir = TkVariable.new(defaultoutputdir)

# Set up the style for a Quake-like theme
def quake_style(widget)
  widget.configure(
    'background' => '#1e1e1e', # Dark gray background
    'foreground' => '#e0e0e0', # Light gray text
    'borderwidth' => 2,
    'relief' => 'raised'
  )
end

# Font style for Quake look
quake_font = TkFont.new :family => 'Courier New', :size => 12, :weight => 'bold'

# Create labels and text fields
lblTitle = Tk::Tile::Label.new(root) do
  text 'MAKEWAD'
  font quake_font
  background '#1e1e1e'
  foreground '#e0e0e0'
end.grid

lblDescription = Tk::Tile::Label.new(root) do
  text 'Create a Quake1 WAD from a folder of PNG files'
  font quake_font
  background '#1e1e1e'
  foreground '#e0e0e0'
end.grid

lblTextures = TkLabel.new(root) { text 'Textures:' }
lblPalette = TkLabel.new(root) { text 'Palette:' }
lblOutputWad = TkLabel.new(root) { text 'Output WAD:' }

txtTextures = TkEntry.new(root) { textvariable $texturedir; width 50 }
txtPalette = TkEntry.new(root) { textvariable $palettedir; width 50 }
txtOutputWad = TkEntry.new(root) { textvariable $outputdir; width 50 }

# Apply Quake style to labels and text fields
[ lblTextures, lblPalette, lblOutputWad ].each { |label| quake_style(label) }
[ txtTextures, txtPalette, txtOutputWad ].each { |entry| quake_style(entry) }

# Create buttons
btnTextures = TkButton.new(root) {
  text 'Select Texture Folder'
  command {
    selected_texture_dir = Tk::chooseDirectory
    $texturedir.value = selected_texture_dir unless selected_texture_dir.empty?
  }
}
quake_style(btnTextures)

btnPalette = TkButton.new(root) {
  text 'Select Palette'
  command {
    selected_palette = Tk::getOpenFile('filetypes' => [['LMP files', '.lmp'], ['All files', '.*']])
    $palettedir.value = selected_palette unless selected_palette.empty?
  }
}
quake_style(btnPalette)

btnOutputWad = TkButton.new(root) {
  text 'Select Output WAD'
  command {
    selected_output = Tk::getSaveFile('filetypes' => [['WAD files', '.wad']])
    $outputdir.value = selected_output unless selected_output.empty?
  }
}
quake_style(btnOutputWad)

# --- Function to Make the WAD ---
def make_wad(texture_dir, palette_file, output_wad)
  palette = MakeWad::Palette.from_file(palette_file)
  wad = MakeWad::TextureWad.new(palette)
  wad.add_directory(texture_dir)
  wad.to_file(output_wad)

  # Open the directory where the wad was just saved
  system("explorer \"#{output_wad}\"")

  puts "WAD successfully created at #{output_wad}"
end

# Button to trigger WAD creation
btnMakeWad = TkButton.new(root) {
  text 'Make WAD'
  command {
    texture_dir = $texturedir.value
    palette_file = $palettedir.value
    output_wad = $outputdir.value

    # Simple validation
    if texture_dir.empty? || palette_file.empty? || output_wad.empty?
      puts "Please fill in all fields before proceeding."
    else
      # Call the make_wad function with GUI inputs
      make_wad(texture_dir, palette_file, output_wad)
    end
  }
}
quake_style(btnMakeWad)

# --- Layout using grid ---
lblTitle.grid('row' => 0, 'column' => 0, 'columnspan' => 3, 'padx' => 10, 'pady' => 5)
lblDescription.grid('row' => 1, 'column' => 0, 'columnspan' => 3, 'padx' => 10, 'pady' => 0)

lblTextures.grid('row' => 2, 'column' => 0, 'padx' => 10, 'pady' => 10)
txtTextures.grid('row' => 2, 'column' => 1, 'padx' => 10, 'pady' => 10)
btnTextures.grid('row' => 2, 'column' => 2, 'padx' => 10, 'pady' => 10)

lblPalette.grid('row' => 3, 'column' => 0, 'padx' => 10, 'pady' => 10)
txtPalette.grid('row' => 3, 'column' => 1, 'padx' => 10, 'pady' => 10)
btnPalette.grid('row' => 3, 'column' => 2, 'padx' => 10, 'pady' => 10)

lblOutputWad.grid('row' => 4, 'column' => 0, 'padx' => 10, 'pady' => 10)
txtOutputWad.grid('row' => 4, 'column' => 1, 'padx' => 10, 'pady' => 10)
btnOutputWad.grid('row' => 4, 'column' => 2, 'padx' => 10, 'pady' => 10)

btnMakeWad.grid('row' => 5, 'column' => 0, 'columnspan' => 3, 'padx' => 10, 'pady' => 20)

# Start the Tk main event loop
Tk.mainloop
