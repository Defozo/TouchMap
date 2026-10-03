import { FrameCallback } from '@kit.ArkUI';
import { Progress } from '../domain/types';

export interface RestorationObservation {
  sequence: number;
  intentAtMs: number;
  frameEndedAtMs: number;
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

/** API20 callback runs at the end of the requested frame, after pending UI layout work. */
export class RestorationFrame extends FrameCallback {
  private completed: boolean = false;
  private report: () => void;
  constructor(report: () => void) { super(); this.report = report; }
  onFrame(_frameTimeInNano: number): void {}
  onIdle(_timeLeftInNano: number): void {
    if (!this.completed) { this.completed = true; this.report(); }
  }
}
