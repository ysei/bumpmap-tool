(* Convert heightmap (intensity; whiter -> higher levels) into intensity-alpha
   (S, T) offsets.  *)

open Color

(* Return height of pixel, as float between 0 and 1.  *)

let get_height img xpos ypos =
  let pix = Rgba32.get img xpos ypos in
  (float_of_int (pix.color.Rgb.r + pix.color.Rgb.g + pix.color.Rgb.b))
  /. (3. *. 255.)

let x_slope img xpos ypos xsize =
  if xpos = 0 then
    let x0 = get_height img xpos ypos
    and x1 = get_height img (xpos + 1) ypos in
    x1 -. x0
  else if xpos = xsize - 1 then
    let x0 = get_height img (xpos - 1) ypos
    and x1 = get_height img xpos ypos in
    x1 -. x0
  else
    let x0 = get_height img (xpos - 1) ypos
    and x1 = get_height img xpos ypos
    and x2 = get_height img (xpos + 1) ypos in
    ((x2 -. x1) +. (x1 -. x0)) /. 2.0

let y_slope img xpos ypos ysize =
  if ypos = 0 then
    let y0 = get_height img xpos ypos
    and y1 = get_height img xpos (ypos + 1) in
    y1 -. y0
  else if ypos = ysize - 1 then
    let y0 = get_height img xpos (ypos - 1)
    and y1 = get_height img xpos ypos in
    y1 -. y0
  else
    let y0 = get_height img xpos (ypos - 1)
    and y1 = get_height img xpos ypos
    and y2 = get_height img xpos (ypos + 1) in
    ((y2 -. y1) +. (y1 -. y0)) /. 2.0

let slope_int s =
  let si = int_of_float (-.s *. 128.0) in
  let si = min si 127 in
  let si = max si (-128) in
  si + 128

let make_rgba32 img =
  match img with
    Images.Index8 i -> Index8.to_rgba32 i
  | Images.Index16 i -> Index16.to_rgba32 i
  | Images.Rgb24 i -> Rgb24.to_rgba32 i
  | Images.Rgba32 i -> i
  | Images.Cmyk32 i -> failwith "CMYK images unsupported"

let make_offset_img oimg img xsize ysize inverse =
  for x = 0 to xsize - 1 do
    for y = 0 to ysize - 1 do
      let x_s = slope_int (x_slope img x y xsize)
      and y_s = slope_int (y_slope img x y ysize) in
      let x_s' = if inverse then 255 - x_s else x_s
      and y_s' = if inverse then 255 - y_s else y_s in
      (* S-difference in the alpha channel, T-difference in the intensity
         channel.  *)
      Rgba32.set oimg x y { color = { Rgb.r = y_s'; g = y_s'; b = y_s' };
			    alpha = x_s' }
    done
  done

let convert_blender_normalmap oimg img xsize ysize inverse =
  for x = 0 to xsize - 1 do
    for y = 0 to ysize - 1 do
      let ipix = Rgba32.get img x ((ysize - 1) - y) in
      let xslope = ipix.color.Rgb.g
      and yslope = ipix.color.Rgb.r in
      let xslope' = if inverse then 255 - xslope else xslope
      and yslope' = if inverse then 255 - yslope else yslope in
      Rgba32.set oimg x y
        { color = { Rgb.r = xslope'; g = xslope'; b = xslope' };
	  alpha = yslope' }
    done
  done

let convert_blender_objspace_normalmap oimg img xsize ysize =
  for x = 0 to xsize - 1 do
    for y = 0 to ysize - 1 do
      let ipix = Rgba32.get img x ((ysize - 1) - y) in
      let r = ipix.color.Rgb.r
      and g = ipix.color.Rgb.g
      and b = ipix.color.Rgb.b in
      Rgba32.set oimg x y
        { color = { Rgb.r = 0; g = r; b = g };
	  alpha = b }
    done
  done

let string_of_img_format = function
    Images.Gif -> "gif"
  | Images.Bmp -> "bmp"
  | Images.Jpeg -> "jpeg"
  | Images.Tiff -> "tiff"
  | Images.Png -> "png"
  | Images.Xpm -> "xpm"
  | Images.Ppm -> "ppm"
  | Images.Ps -> "ps"

let _ =
  let infile = ref ""
  and outfile = ref ""
  and blender_mode = ref false
  and blender_objspace_mode = ref false
  and inverse = ref false in
  let argspec =
    ["-o", Arg.Set_string outfile, "Set output file";
     "-i", Arg.Set inverse, "Invert (black for high points)";
     "-b", Arg.Set blender_mode, "Blender tangent normalmap mode";
     "-B", Arg.Set blender_objspace_mode, "Blender object-space normal mode"]
  and usage = "Usage: bumpmap [-i] [-b] infile -o outfile" in
  Arg.parse argspec (fun name -> infile := name) usage;
  if !infile = "" || !outfile = "" then begin
    Arg.usage argspec usage;
    exit 1
  end;
  let img = Images.load !infile [] in
  let xsize, ysize = Images.size img in
  Printf.printf "Got image: size %d x %d\n" xsize ysize;
  let offsetimg = Rgba32.create xsize ysize in
  if !blender_mode then
    convert_blender_normalmap offsetimg (make_rgba32 img) xsize ysize !inverse
  else if !blender_objspace_mode then
    convert_blender_objspace_normalmap offsetimg (make_rgba32 img) xsize ysize
  else
    make_offset_img offsetimg (make_rgba32 img) xsize ysize !inverse;
  let ofmt = Images.guess_format !outfile in
  Printf.printf "Saving as format: %s\n" (string_of_img_format ofmt);
  Images.save !outfile (Some ofmt) [] (Images.Rgba32 offsetimg)
