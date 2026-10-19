/*
 * AuthService.ets
 *
 * 系统身份认证封装 —— 应用锁与保密会话共用。
 * 应用锁允许「锁屏密码 / 人脸 / 指纹」；保密会话仅允许「人脸 / 指纹」。
 * 遵循 ArkTS 严格模式规范：无 any/unknown，无解构，强类型定义。
 */

import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'AuthService';

export class AuthService {
  /** 认证面板是否正在展示；供应用生命周期判断，避免认证期间误触发应用锁。 */
  private static inProgress: boolean = false;

  public static isInProgress(): boolean {
    return AuthService.inProgress;
  }

  /**
   * 拉起系统身份认证面板。
   * @param title 认证面板标题。
   * @param allowPin true=允许锁屏密码（应用锁）；false=仅人脸/指纹（保密会话）。
   * @returns 认证是否通过；取消、失败或能力不可用均返回 false。
   */
  public static authenticate(title: string, allowPin: boolean): Promise<boolean> {
    if (AuthService.inProgress) {
      return Promise.resolve(false);
    }

    const authTypes: userAuth.UserAuthType[] = [
      userAuth.UserAuthType.FACE,
      userAuth.UserAuthType.FINGERPRINT
    ];
    if (allowPin) {
      authTypes.push(userAuth.UserAuthType.PIN);
    }

    let challenge: Uint8Array = new Uint8Array(0);
    try {
      // Reason: challenge 用于防重放；本地认证不校验 token，但仍使用系统随机数满足接口语义。
      challenge = cryptoFramework.createRandom().generateRandomSync(16).data;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'generate challenge failed: %{public}s', String(err));
    }

    const authParam: userAuth.AuthParam = {
      challenge: challenge,
      authType: authTypes,
      authTrustLevel: userAuth.AuthTrustLevel.ATL2
    };
    const widgetParam: userAuth.WidgetParam = {
      title: title
    };

    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      let instance: userAuth.UserAuthInstance | undefined = undefined;
      const callback: userAuth.IAuthCallback = {
        onResult: (result: userAuth.UserAuthResult) => {
          AuthService.inProgress = false;
          if (instance !== undefined) {
            try {
              instance.off('result', callback);
            } catch (err) {
              hilog.warn(DOMAIN, TAG, 'off result failed: %{public}s', String(err));
            }
          }
          resolve(result.result === userAuth.UserAuthResultCode.SUCCESS);
        }
      };

      try {
        instance = userAuth.getUserAuthInstance(authParam, widgetParam);
        instance.on('result', callback);
        AuthService.inProgress = true;
        instance.start();
      } catch (err) {
        AuthService.inProgress = false;
        const error: BusinessError = err as BusinessError;
        hilog.error(DOMAIN, TAG, 'start auth failed, code=%{public}d, message=%{public}s',
          error.code, error.message);
        resolve(false);
      }
    });
  }
}
