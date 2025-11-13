
export enum PMProgressState {
  Prepare = 0,   // PMProgressStatePrepare
  Loading = 1,   // PMProgressStateLoading
  Success = 2,   // PMProgressStateSuccess
  Failed = 3,    // PMProgressStateFailed
}

export interface PMProgressHandlerProtocol {
  /**
   * @param progress 进度，约定可为 0..1 或 0..100（Dart 端兼容即可）
   * @param state 当前状态（PMProgressState）
   */
  notify(progress: number, state: PMProgressState): void;
}
