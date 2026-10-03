import AccessibilityExtensionAbility, { AccessibilityEvent } from '@ohos.application.AccessibilityExtensionAbility';

// Test instrumentation only. This is not a spoken screen reader and cannot
// satisfy the reader-enabled user acceptance gate.
export default class Probe extends AccessibilityExtensionAbility {
  onConnect(): void { console.info('TOUCHMAP_PROBE_CONNECTED'); }
  onDisconnect(): void { console.info('TOUCHMAP_PROBE_DISCONNECTED'); }
  onAccessibilityEvent(event: AccessibilityEvent): void {
    console.info(`TOUCHMAP_PROBE_EVENT type=${event.eventType}`);
  }
}
