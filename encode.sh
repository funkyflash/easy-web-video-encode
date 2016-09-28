#!/bin/bash

if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ $# -eq 0 ]; then
  echo "Usage: $0 <source filename> [--vp9]"
  echo "<source filename> = video to be transcoded"
  echo "--vp9 = live in the future, and also make a vp9/opus container"
  echo ""
  exit 1
fi

# Get the directory and filename
DIR=$(dirname "$1")
FILE=$(basename "$1")

# Go into the directory so the container will work locally
cd $DIR

IN=$1
OUT=$(echo $1 | sed 's/^\(.*\)\.[a-zA-Z0-9]*$/\1/')

echo "--- Encoding: $1"

# We need to detect whether the video is rotated or not in order to
# set the "scale" factor correctly, otherwise we can hit a fatal error
# However, ffmpeg will automatically apply the rotation for us, so we
# just need to ensure the scale is right, not also apply rotation.
ROTATION=$(ffprobe $IN 2>&1 | \grep rotate | awk '{print $3}')
if [ "$ROTATION" == "" ]; then
    # No rotation, use normal scale (height 720, width auto)
    VF="scale=-1:720"
    echo "--- No rotation detected"
else
    # Rotated video; we need to specify the scale the other way around
    # to avoid a fatal "width not divisible by 2 (405x720)" error
    # Instead we'll use (height auto, width 720)
    VF="scale=720:-1"
    echo "--- Rotation detected; changed scale param"
fi

# Count cores, more than one? Use many!
# Uses one less than total (recomendation for webm)
# Doesn't apply to x264 where 0 == auto (webm doesn't support that)
CORES=$(grep -c ^processor /proc/cpuinfo)
if [ "$CORES" -gt "1" ]; then
  CORES="$(($CORES - 1))"
fi

echo "--- Using $CORES threads for webm"

echo "--- vp8 webm, First Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libvpx -threads $CORES -slices 4 -quality good -cpu-used 0 -b:v 1000k -qmin 10 -qmax 42 -maxrate 1000k -bufsize 2000k -vf $VF \
    -an \
    -pass 1 \
    -f webm \
    -y /dev/null

echo "--- vp8 webm, Second Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libvpx -threads $CORES -slices 4 -quality good -cpu-used 0 -b:v 1000k -qmin 10 -qmax 42 -maxrate 1000k -bufsize 2000k -vf $VF \
    -codec:a libvorbis -b:a 128k \
    -pass 2 \
    -f webm \
    -y $OUT-vp8.webm

echo "--- x264 mp4, First Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libx264 -threads 0 -profile:v main -preset slow -b:v 1000k -maxrate 1000k -bufsize 2000k -vf $VF \
    -an \
    -pass 1 \
    -f mp4 \
    -y /dev/null

echo "--- x264 mp4, Second Pass"
ffmpeg -i $IN \
    -hide_banner -loglevel error -stats \
    -codec:v libx264 -threads 0 -profile:v main -preset slow -b:v 1000k -maxrate 1000k -bufsize 2000k -vf $VF \
    -codec:a aac -b:a 128k -strict -2\
    -pass 2 \
    -f mp4 \
    -y $OUT-h264.mp4

if [ "$2" == "--vp9" ]; then

    echo "--- vp9 webm, First Pass"
    ffmpeg -i $IN \
        -hide_banner -loglevel error -stats \
        -codec:v libvpx-vp9 -threads $CORES -speed 4 -b:v 700k -tile-columns 6 -frame-parallel 1 -vf $VF \
        -an \
        -pass 1 \
        -f webm \
        -y /dev/null

    echo "--- vp9 webm, Second Pass"
    ffmpeg -i $IN \
        -hide_banner -loglevel error -stats \
        -codec:v libvpx-vp9 -threads $CORES -speed 1 -b:v 700k -tile-columns 6 -frame-parallel 1 -auto-alt-ref 1 -lag-in-frames 25 -vf $VF \
        -codec:a libopus -b:a 64k \
        -pass 2 \
        -f webm \
        -y $OUT-vp9.webm
fi

rm -f ffmpeg2pass*
