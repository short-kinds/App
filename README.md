# 📰 숏카인즈 (Short Kinds)

> 현대인을 위한 1분 뉴스! 퀴즈와 함께 핵심만 요약해주는 새로운 뉴스 소비 플랫폼

<!-- <p align="center">
  <img src="[여기에 로고나 대표 이미지를 넣어주세요]" width="400">
</p> -->

<br>

## 🤔 프로젝트 개요 (Problem)

긴 기사에 대한 부담감과 뉴스에 대한 관심 부족은 현대 사회의 뉴스 소비 감소로 이어지고 있습니다. **숏카인즈**는 이러한 문제를 해결하기 위해 숏폼 콘텐츠 형식으로 뉴스를 제공하여 사용자들이 쉽고 재미있게 세상 소식을 접할 수 있도록 돕습니다.

<br>

## ✨ 주요 기능 (Features)

* **⚡ 숏폼 뉴스 콘텐츠:** 텍스트, 이미지, 오디오를 결합하여 1분 내외의 핵심 뉴스만 제공합니다.
* **💰 퀴즈 & 리워드 시스템:** 뉴스 시청 후 퀴즈에 참여하면 포인트가 지급되어 적극적인 뉴스 소비를 유도합니다.
* **📊 기사 유사도 분석:** 동일 사건에 대한 여러 언론사의 기사를 비교 분석하여 균형 잡힌 시각을 제공합니다.

<br>

## ⚙️ 핵심 기술 및 아키텍처 (Tech & Architecture)

본 프로젝트는 뉴스 기사 추출부터 콘텐츠 생성까지의 전 과정을 자동화(**End-to-End**)하여 구축되었습니다.

**처리 순서:**
1.  사용자가 뉴스 카테고리를 선택합니다.
2.  **BIG KINDS API**를 활용하여 뉴스 원문을 추출하고 핵심 내용을 요약합니다.
3.  요약된 텍스트를 TTS(Text-to-Speech)로 변환하여 오디오를 생성합니다.
4.  핵심 키워드를 기반으로 프롬프트를 생성하고, **OpenAI API**를 통해 뉴스에 맞는 이미지를 생성합니다.
5.  텍스트, 오디오, 이미지를 결합하여 숏폼 콘텐츠와 퀴즈를 최종 생성합니다.

**주요 기술:**
* **APIs:** BIG KINDS API, OpenAI API, TTS API

<br>

## 📈 기대 효과 (Effects)

* **사회적 효과:** 뉴스를 어렵게 느끼는 사람들의 뉴스 접근성을 높이고, 문해력(Literacy) 향상에 기여합니다.
* **시장적 효과:** 새로운 방식의 뉴스 경험을 제공하며, 이를 통해 다양한 수익 모델 창출이 가능합니다.

<br>

## ✔ App 부분 전체 흐름 (Overall Flow)
위의 과정에서 쇼츠를 생성한 후,

**Multiplexer (MUX)** 를 통해 쇼츠의 스트리밍 서비스를 지원하고, **supabase**를 통하여 만든 쇼츠들의 MUX 링크, quiz, category 등의 정보들과 회원들의 활동, point, 좋아요와 찜 내역 등의 개인 정보들을 관리합니다.

또한, **Flutter**와 **Android Studio**를 통하여 가상 android 환경과 실제 android 환경에서 app이 동작할 수 있도록 하였습니다.

<br>

## 📱 App 주요 기능 (Features)
1. 로그인/로그아웃 기능
2. 관심 카테고리 선택 후, 그에 따른 쇼츠 기사 제공 (언론사 이름, 쇼츠 영상, 유사도 포함)
3. 쇼츠 좋아요, 찜, 공유 기능
4. 더보기 (원문 기사 title, 기자 이름, 날짜 등의 부가적인 정보 제공)
5. 영상 끝나기 5초 전부터 눌러서 퀴즈를 풀 수 있는 팝업
6. 내 활동 (찜, 좋아요, reward 관리)
7. Reward (시청 보상, 퀴즈 정답 보상 등의 일일 보상 및 배지/업적 기능)
8. 포인트로 여러 물품과 교환할 수 있는 상점 기능

<br>

## 📄 supabase에 입력되는 json 파일 예시

```
 {
  "logical_id": "01100901.20250821164323001",
  "title": "SK 최태원, 빌 게이츠 만나…백신 개발·SMR 협력 방안 짠다",
  "outlet_name": "경향신문",
  "reporter": "최선을",
  "category": "IT_과학",
  "trust_score": 90,
  "published_at": "2025-08-21",
  "url" : "https://www.joongang.co.kr/article/25360706",
  "mux": {
    "playback_id": "https://stream.mux.com/8nIbMHXNeRm9W3jmrVIguxrpyqh01sePXUE02Xfqt2iIg.m3u8",
    "playback_policy": "public",
    "duration_seconds": 38
  },
  "quiz": {
    "question": "SK그룹이 협력한 기관은?",
    "options": [
      "이천",
      "게이츠",
      "SK바이오",
      "AI"
    ],
    "answer_index": 1,
    "cta_top": false,
    "seconds_before_end": 5
  }
}
```

<br>

## 📱 스크린샷 (Screenshots)

<p align="center">
  <table>
    <tr>
      <td><img src="images/splash.png"   width="140" alt="splash 화면"></td>
      <td><img src="images/start.png"    width="140" alt="시작 화면"></td>
      <td><img src="images/category.png" width="140" alt="카테고리 선택"></td>
      <td><img src="images/shorts1.png"  width="140" alt="쇼츠"></td>
      <td><img src="images/more.png"     width="140" alt="더보기"></td>
    </tr>
    <tr>
      <td><img src="images/quiz.png"     width="140" alt="퀴즈"></td>
      <td><img src="images/my.png"       width="140" alt="마이페이지"></td>
      <td><img src="images/reward.png"   width="140" alt="보상"></td>
      <td><img src="images/badge.png"    width="140" alt="배지"></td>
      <td><img src="images/shop.png"     width="140" alt="상점"></td>
    </tr>
  </table>
</p>


## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.














