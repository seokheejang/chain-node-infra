---
title: PoS Finality는 validator count가 committee 구조와 맞아야 동작한다
date: 2026-04-08
category: architecture
related: charts/genesis-generator, charts/lighthouse-validator
---

## 컨텍스트

validator 1개로 devnet을 운영했을 때 `finalized_epoch: 0`에서 영구 정체.
블록은 생성되지만 Casper FFG finality가 진행되지 않았다.

## 내용

Ethereum PoS(mainnet preset)의 finality 메커니즘:

1. `SLOTS_PER_EPOCH: 32` → epoch당 32개 committee
2. 각 validator는 epoch당 1개 committee에 배정
3. Justification 조건: 전체 stake의 **2/3(66.67%)** 이상이 target epoch에 attest
4. Finalization: 연속 2 epoch이 justified되면 첫 번째가 finalized

**validator 1개 + mainnet preset 문제:**

```
32개 committee 중 1개에만 validator 배정
→ beacon API에서 participation ~3%로 집계
→ 2/3 임계치(66.67%) 도달 불가
→ justified 진행 안 됨 → finalized 영원히 epoch 0
```

실제 관측 데이터:
```json
{
  "current_epoch_target_attesting_gwei": 1000000000,   // 1 ETH (~3%)
  "current_epoch_active_gwei": 32000000000              // 32 ETH
}
```

**해결**: validator count를 64개로 증가시키면 committee에 골고루 분산되어 finality 정상 동작.

```yaml
# genesis-generator
chainConfig:
  NUMBER_OF_VALIDATORS: "64"
mnemonics:
  - mnemonic: "test test test test test test test test test test test junk"
    count: 64          # NUMBER_OF_VALIDATORS와 반드시 일치

# lighthouse-validator (Pod은 1대, key 64개 관리)
validatorKeys:
  fromMnemonic:
    count: 64
```

주의: `NUMBER_OF_VALIDATORS`와 `mnemonics.count`는 **독립적**이다.
genesis-generator는 mnemonic에서 derive한 key 수만큼만 genesis에 validator를 포함한다.
두 값이 불일치하면 genesis에 의도한 수의 validator가 포함되지 않는다.

## 왜 중요한가

- L2(Optimistic/ZK Rollup), Bridge, Oracle 등 **finalized block 기준으로 동작하는 모든 시스템**이 finality 없이는 작동하지 않음
- validator 1개로도 블록은 생성되므로 겉보기에 정상처럼 보이지만, finality가 진행되지 않는 것은 조용한 실패
- devnet이라도 L2 연동 테스트를 계획한다면 validator count는 최소 64개 이상 필요
