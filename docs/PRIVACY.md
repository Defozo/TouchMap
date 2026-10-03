# Data and deletion

The learner does not need an account. Material files, accepted declarations, bookmarks, interaction profiles, attempts and recovery checkpoints are held in the application's private storage. Exporting a `.touchmap` package includes only teaching material, source and audio. Exporting personal learning history is a separate deliberate action.

Deleting a material removes the selected local revision, its private assets and its associated events/checkpoint. Other retained draft and published revisions remain separately reachable in the library and must be deleted individually. Earlier draft revisions can support Undo and restoration of their source/audio assets. Cleanup removes abandoned staging and unreferenced directories, including the replaced directory after a successful save of the same revision; it does not silently delete every older draft. An immutable published revision is not silently updated when an author edits another revision.

Manual authoring, prepared package import, learning and package export work locally. A service-based SVG conversion sends the selected SVG to that preparation service. Raster analysis additionally sends the sanitised selected image to Gemini after explicit consent. Speech preparation sends reviewed text to ElevenLabs after separate consent. No learner activity is part of either request.

The app displays the configured service address and sends provider requests through that backend. Pairing tokens expire and remain session-local. Provider credentials remain on the server. The service applies bounded input/geometry/archive limits, rate and spend limits and short job retention, and excludes source content and authorization headers from logs.

Application deletion cannot remove an exported copy held elsewhere or guarantee a provider's deletion, account retention or data residency. Consult the applicable provider account configuration and terms before processing sensitive or third-party educational material. Demonstration inputs in this repository are owned, synthetic and nonsensitive.
