"""Remove private metadata from uploaded report photos."""

import io

from django.core.files.base import ContentFile
from PIL import Image, ImageOps, JpegImagePlugin

# Just above a 50 MP phone photo. Decoding uses about 3 bytes per pixel, so this
# keeps a small, highly compressible file from exhausting the server's memory.
MAX_IMAGE_PIXELS = 50_000_000

PILLOW_FORMATS = {".jpg": "JPEG", ".png": "PNG", ".webp": "WEBP"}


def strip_image_metadata(upload, extension):
    """Return a copy of the image holding only its pixels and colour profile.

    Rebuilding the file drops EXIF (including GPS), XMP, comments, and any data
    appended after the image, such as a Samsung motion photo's video. Orientation
    lives in EXIF, so it is applied to the pixels first.

    Raises an exception if the file cannot be decoded; callers must not store it.
    """
    target = PILLOW_FORMATS[extension]
    options = {}

    upload.seek(0)
    original = upload.read()
    with Image.open(io.BytesIO(original), formats=[target]) as source:
        if source.width * source.height > MAX_IMAGE_PIXELS:
            raise ValueError("Image has too many pixels.")

        if source.info.get("icc_profile"):
            options["icc_profile"] = source.info["icc_profile"]

        if target == "JPEG":
            # Reuse the original compression tables to limit generation loss.
            options["qtables"] = source.quantization
            options["subsampling"] = JpegImagePlugin.get_sampling(source)
        elif target == "WEBP":
            options["lossless"] = b"VP8L" in original
            options["quality"] = 90

        image = ImageOps.exif_transpose(source)

    # Some savers fall back to image.info, so keep only what affects the pixels.
    image.info = {
        key: value for key, value in image.info.items() if key == "transparency"
    }

    output = io.BytesIO()
    image.save(output, format=target, **options)
    return ContentFile(output.getvalue(), name=f"photo{extension}")
