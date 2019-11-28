#!/bin/bash
# Generate PDF ready to print with QR codes, based on input from CSV file with columns <phone number> <message>.
FILE_FORMAT="png"
OUT_FORMAT="png"

get_qr_code() {
    # Get static QR code from Swish. Phone number and message will be locked fields.
    # Input is <phone number> <message>.
    # Stored in input/<phone number>/<message>.
    TELNUMMER=$1
    MEDDELANDE=$2
    mkdir -p input/$TELNUMMER
    if [[ ! -f input/$TELNUMMER/$MEDDELANDE.$FILE_FORMAT ]]; then
        echo "Get QR code for $TELNUMMER $MEDDELANDE"
        curl --data "$(jq -n --arg message "$MEDDELANDE" --arg phonenumber "$TELNUMMER" --arg fileformat "$FILE_FORMAT" '{format: $fileformat, size: 1000, message: {value: $message, editable: false}, payee: {value: $phonenumber, editable: false} }')" --header "Content-Type: application/json" --request POST https://mpc.getswish.net/qrg-swish/api/v1/prefilled --output input/$TELNUMMER/$MEDDELANDE.$FILE_FORMAT
    else
        echo "File for $TELNUMMER $MEDDELANDE already exists, will not retrieve new code."
    fi
}

add_message_number_other() {
    # Add number, message and possibly other text to QR code. Input is <phone number> <message> <other>.
    # Output stored in processing/<phone number>/<message>.
    TELNUMMER=$1
    MEDDELANDE=$2
    ANNAT=$3
    mkdir -p processing/$TELNUMMER
    if [[ ! -f processing/$TELNUMMER/$MEDDELANDE.$OUT_FORMAT.skip ]]; then
        echo "Add message and number to $TELNUMMER; $MEDDELANDE; $ANNAT"
        cp input/$TELNUMMER/$MEDDELANDE.$FILE_FORMAT processing/tmp.$FILE_FORMAT # Make a copy to modify
        if [[ ! $FILE_FORMAT == "png" ]]; then
            echo "Convert format"
            convert -density 1200 -resize 1000x1000 processing/tmp.$FILE_FORMAT processing/tmp.png
            rm processing/tmp.$FILE_FORMAT
        fi
        convert processing/tmp.$OUT_FORMAT -gravity North -splice 0x100 -pointsize 100 -annotate +0+50 "$MEDDELANDE" -append processing/tmp.$OUT_FORMAT # Add message
        convert processing/tmp.$OUT_FORMAT -gravity South -splice 0x100 -pointsize 100 -annotate +0+50 "$TELNUMMER" -append processing/tmp.$OUT_FORMAT # Add phone number
        convert processing/tmp.$OUT_FORMAT -gravity South -splice 0x150 -pointsize 75 -annotate +0+20 "$ANNAT" -append processing/tmp.$OUT_FORMAT # Add other
        convert processing/tmp.$OUT_FORMAT -bordercolor Brown -border 10 processing/tmp.$OUT_FORMAT # Add border
        convert processing/tmp.$OUT_FORMAT \
        \( +clone -crop 16x16+0+0  -fill white -colorize 100% \
        -draw 'fill black circle 15,15 5,0' \
        -background White  -alpha shape \
        \( +clone -flip \) \( +clone -flop \) \( +clone -flip \) \
        \) -flatten  processing/tmp.$OUT_FORMAT # Add rounded corners to frame
        convert processing/tmp.$OUT_FORMAT -bordercolor White -border 5 processing/tmp.$OUT_FORMAT # Add white border
        mv processing/tmp.$OUT_FORMAT processing/$TELNUMMER/$MEDDELANDE.$OUT_FORMAT # Move modified image to destination.
    else
        echo "Processed file for $TELNUMMER $MEDDELANDE already exists, skipping."
    fi
}

add_all_messages() {
    # Go through all QR codes in input/*/*, add message and number to those based on folder and filename.
    # Places output in processing/<number>/<message>.
    echo "Add message and number to all images in input directory."
    mkdir -p input/ # Make sure folder exists.
    for directory in $(ls input/ | tr ":" "\n")
    do
        messages=$(ls input/$directory/ | tr ":" "\n")
        for message in $messages
        do
            # Add data to QR code.
            add_message_number $directory ${message%.*}
        done
    done
}

merge_images() {
    # Merge all png files in processing/*/* into single PDF for printing.
    # Output stored as output/printable.pdf
    echo "Merge images to A4 PDF, ready for printing."
    mkdir -p output/ # Create output dir.
    if [[ -d processing ]]; then
        montage -page A4 -bordercolor white -border 20x100 -tile 2x2 -geometry +4+4 processing/*/*.$OUT_FORMAT output/printable.pdf
    else
        echo "No files in processing/ folder, skip montage"
    fi
}

generate_from_csv_file() {
    # Use CSV file as input to run pipeline.
    # Arguments is filename, expected to be of form: <number> <message>
    # Need a blank line at end of file to read last line.
    csvtool readable $1 |while IFS=$';' read -r NUMBER MESSAGE OTHER
    do
        NUMBER=`echo $NUMBER | xargs`
        MESSAGE=`echo $MESSAGE | xargs`
        OTHER=`echo $OTHER | xargs`
        get_qr_code $NUMBER $MESSAGE
        add_message_number_other $NUMBER $MESSAGE "$OTHER"
    done
    # add_all_messages
    merge_images
}

echo "Input argument should be s .csv file with <number> <message> in order to retrieve QR codes."
generate_from_csv_file $1