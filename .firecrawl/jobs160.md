```json
{
  "total_count": 2,
  "jobs": [
    {
      "id": 89806783177,
      "run_id": 30207029289,
      "workflow_name": "Build LDesk macOS DMG",
      "head_branch": "3.1.1",
      "run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/runs/30207029289",
      "run_attempt": 1,
      "node_id": "CR_kwDOTWOwXc8AAAAU6ObCyQ",
      "head_sha": "ac73aa11076f8ce7f9e27615d89734837ef4265a",
      "url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/jobs/89806783177",
      "html_url": "https://github.com/luoda2023/LUODA-v3.0.1/actions/runs/30207029289/job/89806783177",
      "status": "completed",
      "conclusion": "failure",
      "created_at": "2026-07-26T14:53:24Z",
      "started_at": "2026-07-26T14:53:28Z",
      "completed_at": "2026-07-26T15:10:21Z",
      "name": "build-dmg",
      "steps": [
        {
          "name": "Set up job",
          "status": "completed",
          "conclusion": "success",
          "number": 1,
          "started_at": "2026-07-26T14:53:28Z",
          "completed_at": "2026-07-26T14:53:31Z"
        },
        {
          "name": "Checkout",
          "status": "completed",
          "conclusion": "success",
          "number": 2,
          "started_at": "2026-07-26T14:53:31Z",
          "completed_at": "2026-07-26T14:53:33Z"
        },
        {
          "name": "Setup Flutter",
          "status": "completed",
          "conclusion": "success",
          "number": 3,
          "started_at": "2026-07-26T14:53:33Z",
          "completed_at": "2026-07-26T14:54:21Z"
        },
        {
          "name": "Setup Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 4,
          "started_at": "2026-07-26T14:54:21Z",
          "completed_at": "2026-07-26T14:54:28Z"
        },
        {
          "name": "Install rustfmt",
          "status": "completed",
          "conclusion": "success",
          "number": 5,
          "started_at": "2026-07-26T14:54:28Z",
          "completed_at": "2026-07-26T14:54:28Z"
        },
        {
          "name": "Configure Git for private forks",
          "status": "completed",
          "conclusion": "success",
          "number": 6,
          "started_at": "2026-07-26T14:54:28Z",
          "completed_at": "2026-07-26T14:54:28Z"
        },
        {
          "name": "Generate FFI bridge",
          "status": "completed",
          "conclusion": "success",
          "number": 7,
          "started_at": "2026-07-26T14:54:28Z",
          "completed_at": "2026-07-26T14:58:10Z"
        },
        {
          "name": "Generate macOS app icon",
          "status": "completed",
          "conclusion": "success",
          "number": 8,
          "started_at": "2026-07-26T14:58:10Z",
          "completed_at": "2026-07-26T14:58:10Z"
        },
        {
          "name": "Install dependencies via vcpkg",
          "status": "completed",
          "conclusion": "success",
          "number": 9,
          "started_at": "2026-07-26T14:58:10Z",
          "completed_at": "2026-07-26T15:02:34Z"
        },
        {
          "name": "Build Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 10,
          "started_at": "2026-07-26T15:02:34Z",
          "completed_at": "2026-07-26T15:09:57Z"
        },
        {
          "name": "Validate shared chat and UI contracts",
          "status": "completed",
          "conclusion": "failure",
          "number": 11,
          "started_at": "2026-07-26T15:09:57Z",
          "completed_at": "2026-07-26T15:10:17Z"
        },
        {
          "name": "Build Flutter macOS",
          "status": "completed",
          "conclusion": "skipped",
          "number": 12,
          "started_at": "2026-07-26T15:10:17Z",
          "completed_at": "2026-07-26T15:10:17Z"
        },
        {
          "name": "Create DMG",
          "status": "completed",
          "conclusion": "skipped",
          "number": 13,
          "started_at": "2026-07-26T15:10:17Z",
          "completed_at": "2026-07-26T15:10:17Z"
        },
        {
          "name": "Upload DMG",
          "status": "completed",
          "conclusion": "skipped",
          "number": 14,
          "started_at": "2026-07-26T15:10:17Z",
          "completed_at": "2026-07-26T15:10:17Z"
        },
        {
          "name": "Upload to Release",
          "status": "completed",
          "conclusion": "skipped",
          "number": 15,
          "started_at": "2026-07-26T15:10:17Z",
          "completed_at": "2026-07-26T15:10:17Z"
        },
        {
          "name": "Upload runtime logs (always)",
          "status": "completed",
          "conclusion": "success",
          "number": 16,
          "started_at": "2026-07-26T15:10:17Z",
          "completed_at": "2026-07-26T15:10:18Z"
        },
        {
          "name": "Post Setup Flutter",
          "status": "completed",
          "conclusion": "success",
          "number": 31,
          "started_at": "2026-07-26T15:10:18Z",
          "completed_at": "2026-07-26T15:10:18Z"
        },
        {
          "name": "Post Checkout",
          "status": "completed",
          "conclusion": "success",
          "number": 32,
          "started_at": "2026-07-26T15:10:18Z",
          "completed_at": "2026-07-26T15:10:18Z"
        },
        {
          "name": "Complete job",
          "status": "completed",
          "conclusion": "success",
          "number": 33,
          "started_at": "2026-07-26T15:10:18Z",
          "completed_at": "2026-07-26T15:10:18Z"
        }
      ],
      "check_run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/check-runs/89806783177",
      "labels": [
        "macos-14"
      ],
      "runner_id": 1000018028,
      "runner_name": "GitHub Actions 1000018028",
      "runner_group_id": 0,
      "runner_group_name": "GitHub Actions"
    },
    {
      "id": 89806783511,
      "run_id": 30207029289,
      "workflow_name": "Build LDesk macOS DMG",
      "head_branch": "3.1.1",
      "run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/runs/30207029289",
      "run_attempt": 1,
      "node_id": "CR_kwDOTWOwXc8AAAAU6ObEFw",
      "head_sha": "ac73aa11076f8ce7f9e27615d89734837ef4265a",
      "url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/jobs/89806783511",
      "html_url": "https://github.com/luoda2023/LUODA-v3.0.1/actions/runs/30207029289/job/89806783511",
      "status": "completed",
      "conclusion": "skipped",
      "created_at": "2026-07-26T14:53:24Z",
      "started_at": "2026-07-26T14:53:24Z",
      "completed_at": "2026-07-26T14:53:24Z",
      "name": "build-ios",
      "steps": [

      ],
      "check_run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/check-runs/89806783511",
      "labels": [

      ],
      "runner_id": null,
      "runner_name": null,
      "runner_group_id": null,
      "runner_group_name": null
    }
  ]
}

```