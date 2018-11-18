#!/bin/bash

dest_dir="./Art/logo2"

dest_icon_dir="$dest_dir"
dest_splash_dir="$dest_dir"

source_icon="./Art/logo2/TemplateIcon.png"
source_splash_icon="./Art/logo2/TemplateIcon.png"

#Strip source of extraneous metadata nonsense
convert -strip $source_icon $source_icon
convert -strip $source_splash_icon $source_splash_icon

# calculate background color
background=`convert $source_splash_icon[1x1+0+0] -depth 8 txt: | tail -n +2 | sed -n 's/^.*\(#[^ ]*\).*$/\1/p'`
#background=#4081A3
#background=#3985C3
#background_icon=#007FFF
#background_launch=#1C82E1

# Show the user some progress by outputing all commands being run.
set -e

# Table of Icons
# From: http://docs.coronalabs.com/guide/distribution/buildSettings/index.html#appicons
#
# File                    iOS Version  Size (w×h)   Usage
# Icon-60@3x.png          >= 8.0       180 × 180    App Icon — iPhone 6 Plus
# Icon-Small-40@3x.png    >= 8.0       120 × 120    Search   — iPhone 6 Plus
# Icon-Small@3x.png       >= 8.0        87 × 87     Settings — iPhone 6 Plus
# Icon-60.png             >= 7.0        60 × 60     App Icon — iPhone
# Icon-60@2x.png          >= 7.0       120 × 120    App Icon — Retina iPhone
# Icon-76.png             >= 7.0        76 × 76     App Icon — iPad
# Icon-76@2x.png          >= 7.0       152 × 152    App Icon — Retina iPad
# Icon-Small-40.png       >= 7.0        40 × 40     Search/Settings — all devices
# Icon-Small-40@2x.png    >= 7.0        80 × 80     Search/Settings — all devices
# Icon.png                <= 6.1        57 × 57     App Icon — iPhone
# Icon@2x.png             <= 6.1       114 × 114    App Icon — Retina iPhone
# Icon-72.png             <= 6.1        72 × 72     App Icon — iPad
# Icon-72@2x.png          <= 6.1       144 × 144    App Icon — Retina iPad
# Icon-Small-50.png       <= 6.1        50 × 50     Search/Settings — iPad
# Icon-Small-50@2x.png    <= 6.1       100 × 100    Search/Settings — Retina iPad
# Icon-Small.png          <= 6.1        29 × 29     Search/Settings — iPhone
# Icon-Small@2x.png       <= 6.1        58 × 58     Search/Settings — Retina iPhone

# ---- Create Icons ----
function makeIconImage {
    destName=$1
    width=$2
    height=$3

    # Create paper background at the right size
    #convert -background $background_icon -gravity Center $source_splash_paper -extent "$width"x"$height" -colorspace RGB -type TrueColor $destName

    # Resize the logo
    echo "Creating $destName"
    convert $source_icon -resize "$width"x"$height" -type TrueColorMatte -colorspace sRGB $destName

    # Add the logo
    #convert $destName "./tempicon.png" -set colorspace RGB -gravity Center -composite $destName
    #rm "./tempicon.png"
}

# Icons
makeIconImage "$dest_icon_dir/Icon-60@2x.png" 120 120
makeIconImage "$dest_icon_dir/Icon-60@3x.png" 180 180
makeIconImage "$dest_icon_dir/Icon-76.png" 76 76
makeIconImage "$dest_icon_dir/Icon-76@2x.png" 152 152
makeIconImage "$dest_icon_dir/Icon-83.5@2x.png" 167 167
makeIconImage "$dest_icon_dir/Icon-Small-40.png" 40 40
makeIconImage "$dest_icon_dir/Icon-Small-40@2x.png" 80 80
makeIconImage "$dest_icon_dir/Icon-Small-40@3x.png" 120 120
makeIconImage "$dest_icon_dir/iTunesArtwork" 512 512
makeIconImage "$dest_icon_dir/iTunesArtwork@2x" 1024 1024
makeIconImage "$dest_icon_dir/logo44.png" 44 44
makeIconImage "$dest_icon_dir/logo88.png" 88 88
makeIconImage "$dest_icon_dir/logo132.png" 132 132
makeIconImage "$dest_icon_dir/logo600.png" 600 600
makeIconImage "$dest_icon_dir/logo300.png" 300 300
makeIconImage "$dest_icon_dir/logo150.png" 150 150

#makeIconImage "$dest_icon_dir/Icon-Small@3x.png" 87 87
#makeIconImage "$dest_icon_dir/Icon-60.png" 60 60
#makeIconImage "$dest_icon_dir/Icon.png" 57 57
#makeIconImage "$dest_icon_dir/Icon@2x.png" 114 114
#makeIconImage "$dest_icon_dir/Icon-72.png" 72 72
#makeIconImage "$dest_icon_dir/Icon-72@2x.png" 144 144
#makeIconImage "$dest_icon_dir/Icon-Small-50.png" 50 50
#makeIconImage "$dest_icon_dir/Icon-Small-50@2x.png" 100 100
#makeIconImage "$dest_icon_dir/Icon-Small.png" 29 29
#makeIconImage "$dest_icon_dir/Icon-Small@2x.png" 58 58

# Table of launch images
# Based on: http://docs.coronalabs.com/guide/distribution/buildSettings/index.html#launchimage
#
# File                              Size (w×h)     Orientation     Usage                            Highest Supported iOS
# Default.png                       320 × 480      portrait        iPhone 1,3G,3GS,iPodTouch1,2,3   iOS6.1.6
# Default@2x.png                    640 × 960      portrait        iPhone 4,4s,iPodTouch 4          iOS8 (latest)
# Default-568h@2x.png               640 × 1136     portrait        iPhone 5,5C,5S,iPodTouch 5       iOS8 (latest)
# Default-667h@2x.png               750 × 1334     portrait        iPhone 6                         iOS8 (latest)
# Default-736h@3x.png              1242 × 2208     portrait        iPhone 6+                        iOS8 (latest)
# Default-Landscape-568h@2x.png    1136 × 640      landscape       iPhone 5,5C,5S,iPodTouch 5       iOS8 (latest)
# Default-Landscape-667h@2x.png    1334 × 750      landscape       iPhone 6                         iOS8 (latest)
# Default-Landscape-736h@3x.png    2208 × 1242     landscape       iPhone 6+                        iOS8 (latest)
# Default-Portrait.png              768 × 1024     portrait        iPad 1, 2, Mini 1st gen          iOS8 (latest)
# Default-Portrait@2x.png          1536 × 2048     portrait        iPad 3, 4, Air, Mini 2nd gen     iOS8 (latest)
# Default-Landscape.png            1024 × 768      landscape       iPad 1, 2, Mini 1st gen          iOS8 (latest)
# Default-Landscape@2x.png         2048 × 1536     landscape       iPad 3, 4, Air, Mini 2nd gen     iOS8 (latest)

# --- Create Launch Images ---
function makeLaunchImage {
    destName=$1
    width=$2
    height=$3

    # Landscape images need to be rotated
    rotate="";
    if (( $width > $height )); then
        tempWidth=$width
        width=$height
        height=$tempWidth
        rotate="-rotate 90"
    fi

    iconWidth=$((80*$width/100))
    iconHeight=$(((80*$height)/(100)))

    lobsterWidth=$((20*$width/100))
    lobsterOffset=$((3*$width/100))

    echo Creating "$dest_splash_dir/$1.png"
    # Create paper background at the right size
    #convert -background $background_launch -gravity Center $source_splash_paper -extent "$width"x"$height" -colorspace RGB -type TrueColor "$dest_splash_dir/$1.png"

    # Resize the logo
    convert $source_splash_icon -resize "$iconWidth"x"$iconHeight" -gravity Center -type TrueColorMatte -colorspace sRGB -extent "$width"x"$height" "$dest_splash_dir/$1.png"
    
    # Add the logo
    #convert "$dest_splash_dir/$1.png" "./tempicon.png" -set colorspace RGB -gravity Center -composite "$dest_splash_dir/$1.png"
    #rm "./tempicon.png"

    # Add the lobster
    #convert "$dest_splash_dir/$1.png" -gravity NorthWest -set colorspace RGB $source_splash_corner -geometry "$lobsterWidth"x"$lobsterWidth"+"$lobsterOffset"+"$lobsterOffset" -composite "$dest_splash_dir/$1.png"

    # Rotate as needed
    convert  -set colorspace RGB "$dest_splash_dir/$1.png" $rotate -depth 8 "$dest_splash_dir/$1.png"
}

# iPhone launch images
#makeLaunchImage launch1242x2208  1242 2208
#makeLaunchImage launch750x1334    750 1334
#makeLaunchImage launch2208x1242  2208 1242
#makeLaunchImage launch640x960     640  960
#makeLaunchImage launch640x1136    640 1136

# iPad launch images
#makeLaunchImage launch768x1024    768 1024
#makeLaunchImage launch1536x2048  1536 2048
#makeLaunchImage launch1024x768   1024  768
#makeLaunchImage launch2048x1536  2048 1536
