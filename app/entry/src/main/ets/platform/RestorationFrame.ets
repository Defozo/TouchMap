import { FrameCallback, UIContext } from '@kit.ArkUI';
import { Progress } from '../domain/types';

export interface RestorationObservation {
  sequence: number;
  intentAtMs: number;
  idleAtMs: number;
  checkpointLoadedAtMs: number;
  stateAppliedAtMs: number;
  frameQueuedAtMs: number;
  frameStartedAtMs: number;
  layoutDoneAtMs: number;
  drawCommandAtMs: number;
  idleDurationMs: number;
  durationMs: number;
  page: string;
  packageId: string;
  contentRevision: number;
  stateRevision: number;
  lastRegionId: string;
  activeQuestionId: string;
  selectedAnswers: string[];
  submittedCount: number;
  paused: boolean;
  progress: Progress;
}

export interface RestorationFramePhases { frameStartedAtMs: number; layoutDoneAtMs: number; drawCommandAtMs: number; }

/** Record layout/draw boundaries separately from the possibly deferred idle callback. */
export class RestorationFrame extends FrameCallback {
  private completed: boolean = false;
  private frameStartedAtMs: number = 0;
  private layoutDoneAtMs: number = 0;
  private drawCommandAtMs: number = 0;
  private context: UIContext;
  private layoutCallback: () => void;
  private drawCallback: () => void;
  private report: (phases: RestorationFramePhases) => void;
  constructor(context: UIContext, report: (phases: RestorationFramePhases) => void) {
    super(); this.context = context; this.report = report;
    this.layoutCallback = () => { if (this.frameStartedAtMs > 0 && this.layoutDoneAtMs === 0) { this.layoutDoneAtMs = Date.now(); } };
    this.drawCallback = () => { if (this.layoutDoneAtMs > 0 && this.drawCommandAtMs === 0) { this.drawCommandAtMs = Date.now(); } };
    context.getUIObserver().on('didLayout', this.layoutCallback);
    context.getUIObserver().on('willDraw', this.drawCallback);
  }
  onFrame(_frameTimeInNano: number): void { this.frameStartedAtMs = Date.now(); }
  onIdle(_timeLeftInNano: number): void {
    if (!this.completed) {
      this.completed = true;
      this.context.getUIObserver().off('didLayout', this.layoutCallback);
      this.context.getUIObserver().off('willDraw', this.drawCallback);
      this.report({frameStartedAtMs:this.frameStartedAtMs,layoutDoneAtMs:this.layoutDoneAtMs,drawCommandAtMs:this.drawCommandAtMs});
    }
  }
}
