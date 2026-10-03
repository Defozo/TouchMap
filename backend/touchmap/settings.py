from dataclasses import dataclass, field
import os
from pathlib import Path

@dataclass
class Settings:
    state_dir: Path = field(default_factory=lambda:Path(os.getenv("TOUCHMAP_STATE_DIR",".state")))
    remote: bool = field(default_factory=lambda:os.getenv("TOUCHMAP_REMOTE","false").lower()=="true")
    signing_key: str = field(default_factory=lambda:os.getenv("TOUCHMAP_SESSION_SIGNING_KEY",""),repr=False)
    ai_enabled: bool = field(default_factory=lambda:os.getenv("TOUCHMAP_CLOUD_AI_ENABLED","false").lower()=="true")
    tts_enabled: bool = field(default_factory=lambda:os.getenv("TOUCHMAP_CLOUD_TTS_ENABLED","false").lower()=="true")
    google_key: str = field(default_factory=lambda:os.getenv("GOOGLE_AI_STUDIO_API_KEY",""),repr=False)
    eleven_key: str = field(default_factory=lambda:os.getenv("ELEVENLABS_API_KEY",""),repr=False)
    gemini_model: str = field(default_factory=lambda:os.getenv("GEMINI_MODEL","gemini-3.8-flash"))
    tts_model: str = field(default_factory=lambda:os.getenv("ELEVENLABS_MODEL_ID","eleven_flash_v2_5"))
    voice: str = field(default_factory=lambda:os.getenv("ELEVENLABS_VOICE_ID","hpp4J3VqNfWAUOO0d1Us"))
    analyses_per_session: int = field(default_factory=lambda:int(os.getenv("TOUCHMAP_ANALYSES_PER_SESSION","20")))
    generation_ceiling: int = field(default_factory=lambda:int(os.getenv("TOUCHMAP_GENERATION_CEILING","100")))
    spend_ceiling_usd: float = field(default_factory=lambda:float(os.getenv("TOUCHMAP_SPEND_CEILING_USD","10")))
    retry_window_seconds: int = 600
    session_seconds: int = 3600

    def validate(self):
        if self.remote and len(self.signing_key)<32:
            raise ValueError("Remote mode requires backend-only TOUCHMAP_SESSION_SIGNING_KEY with at least 32 characters")
        if self.gemini_model!="gemini-3.8-flash" or self.tts_model!="eleven_flash_v2_5":
            raise ValueError("This release validates only the documented model IDs")
        if not self.voice.isalnum() or self.spend_ceiling_usd<=0 or self.analyses_per_session<=0 or self.generation_ceiling<=0:
            raise ValueError("Invalid operator configuration")
