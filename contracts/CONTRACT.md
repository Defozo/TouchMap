# TouchMap contract v1

Authoritative implementation wire contract. Coordinates are source coordinates, x then y.

`Point = {x:number,y:number}`. `Polygon = {outer:Point[],holes:Point[][]}`.

`Diagram = {schemaVersion:1, packageId:string, revision:number, title:string, language:string, source:Source, regions:Region[], relations:Relation[], charts:Chart[], questions:Question[], audio:Audio[], description:string}`.

`Source = {id:string, sha256:string, width:number, height:number, path:string, attribution:string, license:string, viewBox:number[], previewPath?:string, previewSha256?:string}` (viewBox x,y,width,height). The optional preview fields occur together and identify a PNG rasterization of the source at exactly its declared dimensions. The original source remains the provenance/evidence reference. SVG preparation includes a PNG because the tested native SVG decoder omits text and markers. Both original and preview must pass manifest and source hashes; a preview is never reconstructed from proposed AI semantics.

`Evidence = {sourceId:string, reference:string, origin:'source-derived'|'human-authored'|'AI-proposed'}`.

`Review = {status:'draft'|'needs_review'|'reviewed', revision:number, reviewer:string, issues:string[]}`. Region geometry and meaning reviews are independent.

`Region = {id:string,label:string,description:string,polygons:Polygon[],line:Point[],lineWidth:number,zIndex:number,readingOrder:number,evidence:Evidence[],geometryReview:Review,meaningReview:Review}`. At least polygons or line must be present. Lines require >=2 points. Rings require >=3 distinct finite points.

`Relation = {id:string,fromId:string,toId:string,label:string,type:string,direction:'forward'|'both'|'unknown',path:Point[]|null,evidence:Evidence[],review:Review}`. Unknown paths remain null. Unknown direction cannot answer a direction question.

`Chart = {id:string,title:string,kind:'bar'|'line',xAxis:Axis,yAxis:Axis,series:Series[],evidence:Evidence[],review:Review}`.
`Axis = {label:string,unit:string,scale:'linear'|'log'|'category',domain:number[],ticks:Tick[]}`; `Tick={value:number,label:string}`.
`Series={id:string,label:string,values:ChartValue[]}`; `ChartValue={id:string,regionId:string,x:string,value:number|null,precision:number,evidence:Evidence[]}`.

`Question = {id:string,prompt:string,type:'adjacency'|'direction'|'sequence'|'comparison'|'value',factIds:string[],options:AnswerOption[],acceptedAnswers:string[],hint:string,explanation:string,requiredRevision:number,review:Review}`; `AnswerOption={id:string,label:string}`. Acceptance uses exact option IDs and only reviewed facts. No AI grading.

`Audio={id:string,targetId:string,kind:'label'|'description'|'question'|'overview',path:string,textHash:string,language:string,provider:string,voice:string,sha256:string,durationMs:number}`.

`Manifest={schemaVersion:1,packageId:string,revision:number,title:string,language:string,author:{name:string,declaration:string},license:string,assets:Asset[]}`; `Asset={path:string,sha256:string,bytes:number,mediaType:string}`. Manifest assets cover diagram.json, source and all audio, never manifest itself. ZIP uses UTF-8 portable relative paths; import never trusts declarations as receiver acceptance. Packages exclude progress and profiles.

API results: `{requestId,contractVersion:1,sourceHash,draftRevision,provider,model,result}`. Errors `{error:{code,message},requestId}`. SVG and image use multipart file, draftRevision, language, requestId; image requires consent=true and sourceHash. Audio uses JSON `{requestId,sourceHash,draftRevision,language,consent,labels:[{targetId,kind,text,textHash}]}`. Server model and voice are operator-controlled.

All learning actions include unique eventId and expected stateRevision. A submitted answer is distinct from an unfinished selection. Content revisions are immutable; editing invalidates reviews, audio and dependent questions. Local acceptance is not package metadata.
