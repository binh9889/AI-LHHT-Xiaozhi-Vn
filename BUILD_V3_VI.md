# Build AI-LHHT v3.0 Voice Pro

## Cách thay source cũ bằng v3
1. Backup branch hiện tại.
2. Giải nén source v3 vào thư mục tạm.
3. Rsync toàn bộ source vào repo, giữ `.git`.
4. Commit/push lên branch `develop-v3` trước.
5. Vào GitHub Actions → `Build AI-LHHT v3 Voice Pro APK` → Run workflow.

## Lệnh đề xuất trong Codespaces
```bash
cd /workspaces/AI-LHHT-Xiaozhi-Vn
git branch backup-v2.2-before-v3
git push origin backup-v2.2-before-v3

git checkout -b develop-v3

rm -rf /tmp/ailhht-v3
mkdir -p /tmp/ailhht-v3
unzip -q AI-LHHT-v3.0.0-Voice-Pro-VI-build-ready.zip -d /tmp/ailhht-v3

rsync -a --delete \
  --exclude='.git/' \
  --exclude='AI-LHHT-v3.0.0-Voice-Pro-VI-build-ready.zip' \
  /tmp/ailhht-v3/AI-LHHT-v3.0.0-Voice-Pro-VI/ \
  /workspaces/AI-LHHT-Xiaozhi-Vn/

git status --short
git add -A
git commit -m "AI-LHHT v3.0 Voice Pro with AI interpreter"
git push -u origin develop-v3
```

## Build
Workflow tạo:
`AI-LHHT-v3.0.0-Voice-Pro-VI.apk`

Chỉ merge `develop-v3` vào `main` sau khi workflow PASS và test trên điện thoại thật.
