#!/usr/bin/env bash
exec gphoto2 --stdout --capture-movie | ffmpeg -hide_banner -i - -vcodec rawvideo -pix_fmt yuv420p -threads 0 -f v4l2 /dev/video10
