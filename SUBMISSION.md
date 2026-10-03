# TouchMap

**Challenge:** IMAGINE WHAT'S NEXT, HackYeah 2026  
**Team:** DEFOZO SOFTWARE HOUSE  
**Team member:** Michał Kiełtyka  
**Human team size:** 1  
**Primary area:** Human-Centric Technology, accessibility and education  
**Supporting area:** Intelligent Experiences, optional AI authoring

A learner who cannot see a diagram still needs to understand what connects to what. A spoken description follows someone else's order. TouchMap lets the learner choose the object, hear its label and follow the connection that answers their question.

TouchMap is a native OpenHarmony application for blind and low-vision learners and the teachers who prepare their materials. On the water-cycle diagram, touch **Evaporation**, hear its name and follow **Vapour cools into droplets** to **Condensation**. The same actions work through a list or single-button scanning. A lesson asks about the connection, checks the selected answer against the reviewed diagram and explains the result.

Teachers import a source image, review the objects and relationships, add questions and publish a portable `.touchmap` lesson. Optional Gemini analysis supplies an editable first draft. Teachers can import recordings or generate speech with ElevenLabs. The finished package carries its source and audio, so learners can use it offline without an account or API key.

Learning can stop halfway through an answer. TouchMap saves the last object, submitted answers and unfinished selection, then restores that context when the learner returns. Teachers can share the lesson with another installation while each learner keeps their own progress.

The demonstration shows the actual native app on the Oniro/OpenHarmony emulator, including touch and recorded speech, a directed connection, explicit answer submission, recovery after a restart and teacher preparation. The bundled lessons include a water cycle, an unfamiliar branching process, a rainfall chart and a short tutorial. Native file picking, local audio and transactional storage support the complete workflow.

[Watch the three-minute narrated demonstration, open the presentation and download the signed app](https://github.com/Defozo/TouchMap/releases/tag/v1.0.1). The [guided demo](docs/DEMO_ACCESS.md) takes a reviewer through a lesson without a TouchMap account. The [public repository](https://github.com/Defozo/TouchMap) contains the reproducible build and installation instructions, [architecture](ARCHITECTURE.md), [AI development workflow](AI_WORKFLOW.md) and [AI integration documentation](AI_INTEGRATION.md). Detailed validation evidence and its scope are in the [technical test report](docs/TEST_REPORT.md).
