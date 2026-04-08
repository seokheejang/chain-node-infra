---
title: genesis-generator의 SLOT_DURATION_MS와 SECONDS_PER_SLOT 불일치
date: 2026-04-08
category: debugging
related: charts/genesis-generator, ethpandaops/ethereum-genesis-generator
---

## 컨텍스트

devnet 블록 시간을 3초로 설정하려고 `SLOT_DURATION_IN_SECONDS: "3"`을 지정했으나,
실제 블록 간격이 12초로 유지되는 문제를 발견했다.

## 내용

genesis-generator(ethpandaops) 이미지 내부의 CL config 템플릿:

```yaml
# /config/cl/config.yaml (이미지 내부)
SECONDS_PER_SLOT: $SLOT_DURATION_IN_SECONDS    # ← 입력 env var에서 치환
SLOT_DURATION_MS: $SLOT_DURATION_MS             # ← 별도 env var (기본값: mainnet preset 12000)
```

- `SLOT_DURATION_IN_SECONDS` → `SECONDS_PER_SLOT`만 설정
- `SLOT_DURATION_MS`는 **별도 env var** `$SLOT_DURATION_MS`로 제어되며, 미설정 시 mainnet preset 기본값 `12000` 유지
- Lighthouse는 **`SLOT_DURATION_MS`를 `SECONDS_PER_SLOT`보다 우선** 사용 (`SECONDS_PER_SLOT`은 deprecated)

결과: `SECONDS_PER_SLOT: 3` + `SLOT_DURATION_MS: 12000` → Lighthouse는 12초로 동작.

**해결**: 두 값을 반드시 함께 설정해야 한다.

```yaml
# genesis-generator values
chainConfig:
  SLOT_DURATION_IN_SECONDS: "3"
  SLOT_DURATION_MS: "3000"              # SLOT_DURATION_IN_SECONDS * 1000
```

## 왜 중요한가

- 이 불일치는 조용히 발생한다 (에러 로그 없음, 블록이 그냥 12초 간격으로 생성됨)
- genesis-generator의 env var 이름과 CL spec 필드 이름이 다르기 때문에 혼동하기 쉽다
- devnet/testnet에서 빠른 블록 시간을 원하면 반드시 두 값 모두 설정 확인 필요
