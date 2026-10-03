import io
import warnings
from PIL import Image, ImageOps, UnidentifiedImageError
from .errors import TouchMapError

def normalize_image(data: bytes) -> tuple[bytes,int,int]:
    if len(data)>10*1024*1024:
        raise TouchMapError("image_limit","Image exceeds 10 MiB",413)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error",Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as original:
                if original.format not in ("PNG","JPEG"):
                    raise TouchMapError("image_type","Only PNG and JPEG are supported")
                if original.width*original.height>20_000_000 or getattr(original,"n_frames",1)!=1:
                    raise TouchMapError("image_dimensions","Image exceeds 20 megapixels or contains animation",413)
                original.load()
                image=ImageOps.exif_transpose(original).convert("RGB")
                clean=Image.new("RGB",image.size); clean.paste(image)
                out=io.BytesIO(); clean.save(out,format="PNG")
                return out.getvalue(),clean.width,clean.height
    except (UnidentifiedImageError,OSError,Image.DecompressionBombError,Image.DecompressionBombWarning):
        raise TouchMapError("invalid_image","Invalid or unsafe image") from None
