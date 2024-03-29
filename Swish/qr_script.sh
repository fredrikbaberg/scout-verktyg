#!/bin/bash
# Generate PDF ready to print with QR codes, based on input from CSV file with columns <phone number> <message>.
# Required tools: imagemagick, csvtool.
FILE_EXTENSION="png" # png is supported by both ImageMagick and Swish API. SVG converts terrible.
BORDER_COLOR="Black"
NUMBER_COLOR="Black"
MESSAGE_COLOR="Black"
OTHER_COLOR="Black"
FONT="Roboto"
OUTPUT_DIR="generated_qr"

get_qr_code() {
    # Get static (prefilled) QR code from Swish. Phone number and message will be locked fields.
    # Input is <phone number> <message>.
    # Stored in $OUTPUT_DIR/qr/<phone number>/<message>.
    PHONE_NUMBER=$1
    MESSAGE=$2
    mkdir -p $OUTPUT_DIR/qr/$PHONE_NUMBER
    if [[ ! -f $OUTPUT_DIR/qr/$PHONE_NUMBER/$MESSAGE.$FILE_EXTENSION ]]; then
        echo "Get QR code for $PHONE_NUMBER $MESSAGE"
        curl --data "$(jq -n --arg message "$MESSAGE" --arg phonenumber "$PHONE_NUMBER" --arg fileformat "$FILE_EXTENSION" '{format: $fileformat, size: 1000, message: {value: $message, editable: false}, payee: {value: $phonenumber, editable: false} }')" --header "Content-Type: application/json" --request POST https://mpc.getswish.net/qrg-swish/api/v1/prefilled --output $OUTPUT_DIR/qr/$PHONE_NUMBER/$MESSAGE.$FILE_EXTENSION
    else
        echo "File for $PHONE_NUMBER; $MESSAGE already exists, will not retrieve again."
    fi
}

add_message_number_other() {
    # Add number, message and possibly extra text to QR code. Input is <phone number> <message> <other>.
    # QR code is retrieved from $OUTPUT_DIR/qr/<phone number>/<message>.<FILE_EXTENSION>.
    # Output is stored in $OUTPUT_DIR/processing/<phone number>/<message>.
    PHONE_NUMBER=$1
    MESSAGE=$2
    OTHER=$3
    mkdir -p $OUTPUT_DIR/processing/$PHONE_NUMBER
    if [[ ! -f $OUTPUT_DIR/processing/$PHONE_NUMBER/$MESSAGE.$FILE_EXTENSION ]]; then # Only execute if file does not exist, since it can take some time.
        echo "Add message and number to $PHONE_NUMBER; $MESSAGE; $OTHER"
        cp $OUTPUT_DIR/qr/$PHONE_NUMBER/$MESSAGE.$FILE_EXTENSION $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Make a copy to modify
        convert $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION -gravity North -splice 0x100 -fill "$MESSAGE_COLOR" -pointsize 100 -font "$FONT" -annotate +0+50 "$MESSAGE" -append $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Add message
        convert $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION -gravity South -splice 0x100 -fill "$NUMBER_COLOR" -pointsize 100 -font "$FONT" -annotate +0+50 "$PHONE_NUMBER" -append $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Add phone number
        if [[ ${#OTHER} -gt 0 ]]; then # Add extra text if available.
            convert $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION -gravity South -splice 0x150 -fill "$OTHER_COLOR" -pointsize 75 -font "$FONT" -annotate +0+20 "$OTHER" -append $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Add other text. Optional.
        fi
        convert $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION -bordercolor $BORDER_COLOR -border 10 $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Add border
        convert $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION \
        \( +clone -crop 16x16+0+0  -fill white -colorize 100% \
        -draw 'fill black circle 15,15 5,0' \
        -background White  -alpha shape \
        \( +clone -flip \) \( +clone -flop \) \( +clone -flip \) \
        \) -flatten $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Add rounded corners to frame
        convert $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION -bordercolor White -border 5 $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Add white border
        if [[ -f logo.svg ]]; then
            composite -compose atop -geometry x175+20+20 -gravity northeast -background none logo.svg $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION # Add logo
        fi
        mv $OUTPUT_DIR/processing/tmp.$FILE_EXTENSION $OUTPUT_DIR/processing/$PHONE_NUMBER/$MESSAGE.$FILE_EXTENSION # Move modified image to destination.
    else
        echo "Processed file for $PHONE_NUMBER $MESSAGE already exists, skipping."
    fi
}

merge_images() {
    # Merge all png files in processing/*/* into single A4 sized PDF for printing.
    # Output is stored as $OUTPUT_DIR/output/printable.pdf
    echo "Merge images to A4 PDF, ready for printing."
    mkdir -p $OUTPUT_DIR/output/ # Create output dir.
    if [[ ! -e $OUTPUT_DIR/output/printable.pdf ]]; then
        if [[ -d $OUTPUT_DIR/processing ]]; then
            montage -page A4 -bordercolor white -border 20x100 -tile 2x2 -geometry +4+4 $OUTPUT_DIR/processing/*/*.$FILE_EXTENSION $OUTPUT_DIR/output/printable.pdf
        else
            echo "No files in processing/ folder, skip montage"
        fi
    else
        echo "Output file already exists, skipping."
    fi
}

generate_from_csv_file() {
    # Use CSV file as input to generate printable QR-codes.
    # Arguments is a CSV file, separated by semicolon (;).
    echo "Generate files from CSV file."
    csvtool readable $1 |while IFS=$';' read -r NUMBER MESSAGE OTHER
    do
        NUMBER=`echo $NUMBER | xargs`
        MESSAGE=`echo $MESSAGE | xargs`
        OTHER=`echo $OTHER | xargs`
        get_qr_code $NUMBER $MESSAGE
        add_message_number_other $NUMBER $MESSAGE "$OTHER"
    done
    merge_images
}

add_all_messages() {
    # Go through all QR codes in $OUTPUT_DIR/qr/*/*, add message and number to those based on folder and filename.
    # Places output in $OUTPUT_DIR/processing/<number>/<message>.
    # This bypasses the "other" field, since it is not stored in file path/name.
    echo "Add message and number to all images in $OUTPUT_DIR/qr directory."
    mkdir -p $OUTPUT_DIR/qr/ # Make sure folder exists.
    for directory in $(ls $OUTPUT_DIR/qr/ | tr ":" "\n")
    do
        messages=$(ls $OUTPUT_DIR/qr/$directory/ | tr ":" "\n")
        for message in $messages
        do
            # Add data to QR code.
            add_message_number_other $directory ${message%.*}
        done
    done
}

echo "Input argument should be name of a csv file (separated by ;) with columns: <number>; <message>; <other> for script to retrieve QR codes."
echo "If no file is passed, generate QR codes based on files in folder $OUTPUT_DIR/qr."
if [[ $# -gt 0 ]]; then
    generate_from_csv_file $1
else
    add_all_messages
    merge_images
fi
