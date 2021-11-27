#!/bin/bash
# Generate PDF ready to print with QR codes, based on input from CSV file with columns <phone number> <message>.
# QR codes are retrieved according to https://developer.swish.nu/api/qr-codes/v1#pre-filled-qr-code
# Required tools: imagemagick, csvtool.
FILE_EXTENSION="png"
BORDER_COLOR="Black"
NUMBER_COLOR="Black"
MESSAGE_COLOR="Black"
OTHER_COLOR="Black"
FONT="Roboto"
OUTPUT_DIR="generated_gen"

get_qr_code() {
    # Get static (prefilled) QR code from Swish. Phone number and message will be locked fields.
    # Input is <phone number> <message>.
    # Output is SVG stored in $OUTPUT_DIR/qr/<phone number>/$FILENAME.$FORMAT
    FORMAT=$FILE_EXTENSION
    PHONE_NUMBER=$1
    MESSAGE=$2
    SIZE=1000 # Size of resulting image. Not used for SVG
    BORDER=4 # Margin around QR code
    TRANSPARENT=true
    FILENAME=$3
    mkdir -p $OUTPUT_DIR/qr/"$PHONE_NUMBER"
    if [[ ! -f $OUTPUT_DIR/qr/$PHONE_NUMBER/$FILENAME.$FORMAT ]]; then
        echo "Get QR code for $PHONE_NUMBER $MESSAGE"
        curl --request POST https://mpc.getswish.net/qrg-swish/api/v1/prefilled \
            --header "Content-Type: application/json" \
            --data "$(jq -n --arg fileformat "$FORMAT" --arg phonenumber "$PHONE_NUMBER" --arg message "$MESSAGE" --arg size "$SIZE" --arg border "$BORDER" --arg transparent "$TRANSPARENT" '{format: $fileformat, payee: {value: $phonenumber, editable: false}, message: {value: $message, editable: false}, size: $size, border: $border, transparent: $transparent }')" \
            --output $OUTPUT_DIR/qr/"$PHONE_NUMBER"/"$FILENAME".$FORMAT
    else
        echo "File $FILENAME.$FORMAT for $PHONE_NUMBER; $MESSAGE already exists, will not retrieve again."
    fi
}

add_details() {
    PHONE_NUMBER=$1
    MESSAGE=$2
    OTHER=$3
    FILENAME=$4
    mkdir -p "${OUTPUT_DIR}/processing/${PHONE_NUMBER}"
    echo "Add message, number and logo to $PHONE_NUMBER; $MESSAGE; $OTHER"
    if [[ ! -f logo.svg ]]; then
        echo '<?xml version="1.0" encoding="UTF-8" standalone="no"?><svg version="1.1" width="271" height="272"></svg>' > logo.svg
    fi
    convert \
        "${OUTPUT_DIR}/qr/$PHONE_NUMBER/$FILENAME.$FILE_EXTENSION" \
        \
        -gravity North \
        -background none \
        -splice 0x100 \
        -font "$FONT" \
        -fill "$MESSAGE_COLOR" \
        -pointsize 100 \
        -annotate +0+50 "$MESSAGE" \
        \
        -gravity South \
        -splice 0x100 \
        -fill "$NUMBER_COLOR" \
        -pointsize 100 \
        -font "$FONT" \
        -annotate +0+50 "$PHONE_NUMBER" \
        \
        -gravity South \
        -splice 0x150 \
        -fill "$OTHER_COLOR" \
        -pointsize 75 \
        -font "$FONT" \
        -annotate +0+20 "$OTHER" \
        \
        -alpha set \
        -compose Copy \
        -bordercolor transparent \
        -border 10 \
        \
        logo.svg \
        -gravity northeast \
        -geometry x200-820+00 \
        -composite \
        \
        -alpha set \
        -compose Copy \
        -bordercolor $BORDER_COLOR \
        -border 10 \
        \
        -gravity northwest \
        \( +clone -crop 10x10+0+0  -fill white -colorize 100% \
       -draw 'fill black circle 15,15 15,0' \
       -background White  -alpha set \
       \( +clone -flip \) \( +clone -flop \) \( +clone -flip \) \
     \) -flatten \
        \
        -alpha set \
        -compose Copy \
        -bordercolor White \
        -border 0 \
        \
        "${OUTPUT_DIR}/processing/${PHONE_NUMBER}/${FILENAME}.$FILE_EXTENSION"
}

merge_images() {
    # Merge all png files in processing/*/* into single A4 sized PDF for printing.
    # Output is stored as $OUTPUT_DIR/output/printable.pdf
    echo "Merge images to A4 PDF, ready for printing."
    mkdir -p $OUTPUT_DIR/output/ # Create output dir.
    rm -rf $OUTPUT_DIR/output/printable.pdf
    if [[ ! -e $OUTPUT_DIR/output/printable.pdf ]]; then
        if [[ -d $OUTPUT_DIR/processing ]]; then
            montage -page A4 -bordercolor white -border 80x40 -tile 2x2 -geometry +4+4 $OUTPUT_DIR/processing/*/*.$FILE_EXTENSION $OUTPUT_DIR/output/printable.pdf
        else
            echo "No files in processing/ folder, skip montage"
        fi
    else
        echo "Output file already exists, skipping."
    fi
}


echo "Input argument should be name of a csv file (separated by ;) with columns: <number>; <message>; <additional text> for script to retrieve QR codes."
if [[ $# -gt 0 ]]; then
    ## For each entry in CSV file
    csvtool readable "$1" |while IFS=$';' read -r NUMBER MESSAGE OTHER
    do
        NUMBER=$(echo "$NUMBER" | xargs)
        MESSAGE=$(echo "$MESSAGE" | xargs)
        OTHER=$(echo "$OTHER" | xargs)

        # Generate filename
        STRING=$MESSAGE
        FILENAME="${STRING//_/}" && \
        FILENAME="${FILENAME// /_}" && \
        FILENAME="${FILENAME//[^a-zA-Z0-9]/}" && \
        FILENAME="${FILENAME,,}"

        echo "$FILENAME"

        # Get QR code
        get_qr_code "$NUMBER" "$MESSAGE" "$FILENAME"

        # Combine with text and logo
        add_details "$NUMBER" "$MESSAGE" "$OTHER" "$FILENAME"
        # add_message_number_other $NUMBER $MESSAGE "$OTHER"
    done
    merge_images
else
    echo "No CSV file specified"
fi
