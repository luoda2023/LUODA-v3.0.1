```json
{
  "total_count": 1,
  "jobs": [
    {
      "id": 89884262754,
      "run_id": 30236161053,
      "workflow_name": "Build LDesk Windows EXE",
      "head_branch": "3.1.1",
      "run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/runs/30236161053",
      "run_attempt": 1,
      "node_id": "CR_kwDOTWOwXc8AAAAU7YUBYg",
      "head_sha": "b04e49b0fc218b13375b749c5687cc2c40887a8e",
      "url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/actions/jobs/89884262754",
      "html_url": "https://github.com/luoda2023/LUODA-v3.0.1/actions/runs/30236161053/job/89884262754",
      "status": "in_progress",
      "conclusion": null,
      "created_at": "2026-07-27T04:05:39Z",
      "started_at": "2026-07-27T04:05:42Z",
      "completed_at": null,
      "name": "build-exe (x64)",
      "steps": [
        {
          "name": "Set up job",
          "status": "completed",
          "conclusion": "success",
          "number": 1,
          "started_at": "2026-07-27T04:05:43Z",
          "completed_at": "2026-07-27T04:05:46Z"
        },
        {
          "name": "Run actions/checkout@v4",
          "status": "completed",
          "conclusion": "success",
          "number": 2,
          "started_at": "2026-07-27T04:05:46Z",
          "completed_at": "2026-07-27T04:05:51Z"
        },
        {
          "name": "Verify branded icon assets",
          "status": "completed",
          "conclusion": "success",
          "number": 3,
          "started_at": "2026-07-27T04:05:51Z",
          "completed_at": "2026-07-27T04:05:51Z"
        },
        {
          "name": "Cache Cargo registry",
          "status": "completed",
          "conclusion": "success",
          "number": 4,
          "started_at": "2026-07-27T04:05:51Z",
          "completed_at": "2026-07-27T04:06:01Z"
        },
        {
          "name": "Setup Flutter",
          "status": "completed",
          "conclusion": "success",
          "number": 5,
          "started_at": "2026-07-27T04:06:01Z",
          "completed_at": "2026-07-27T04:07:09Z"
        },
        {
          "name": "Setup Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 6,
          "started_at": "2026-07-27T04:07:09Z",
          "completed_at": "2026-07-27T04:07:21Z"
        },
        {
          "name": "Install rustfmt",
          "status": "completed",
          "conclusion": "success",
          "number": 7,
          "started_at": "2026-07-27T04:07:21Z",
          "completed_at": "2026-07-27T04:07:28Z"
        },
        {
          "name": "Ensure correct cargo version",
          "status": "completed",
          "conclusion": "success",
          "number": 8,
          "started_at": "2026-07-27T04:07:28Z",
          "completed_at": "2026-07-27T04:07:29Z"
        },
        {
          "name": "Configure Git for private forks",
          "status": "completed",
          "conclusion": "success",
          "number": 9,
          "started_at": "2026-07-27T04:07:29Z",
          "completed_at": "2026-07-27T04:07:29Z"
        },
        {
          "name": "Generate FFI bridge",
          "status": "completed",
          "conclusion": "success",
          "number": 10,
          "started_at": "2026-07-27T04:07:29Z",
          "completed_at": "2026-07-27T04:15:00Z"
        },
        {
          "name": "Setup vcpkg",
          "status": "completed",
          "conclusion": "success",
          "number": 11,
          "started_at": "2026-07-27T04:15:00Z",
          "completed_at": "2026-07-27T04:15:36Z"
        },
        {
          "name": "Cache vcpkg installed packages",
          "status": "completed",
          "conclusion": "success",
          "number": 12,
          "started_at": "2026-07-27T04:15:36Z",
          "completed_at": "2026-07-27T04:15:41Z"
        },
        {
          "name": "Install vcpkg deps",
          "status": "completed",
          "conclusion": "success",
          "number": 13,
          "started_at": "2026-07-27T04:15:41Z",
          "completed_at": "2026-07-27T04:15:52Z"
        },
        {
          "name": "Build Rust",
          "status": "completed",
          "conclusion": "success",
          "number": 14,
          "started_at": "2026-07-27T04:15:52Z",
          "completed_at": "2026-07-27T04:28:30Z"
        },
        {
          "name": "Validate direct IP access",
          "status": "in_progress",
          "conclusion": null,
          "number": 15,
          "started_at": "2026-07-27T04:28:30Z",
          "completed_at": null
        },
        {
          "name": "Validate shared chat and UI contracts",
          "status": "pending",
          "conclusion": null,
          "number": 16,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Normalize Windows resource encoding",
          "status": "pending",
          "conclusion": null,
          "number": 17,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Build Flutter Windows",
          "status": "pending",
          "conclusion": null,
          "number": 18,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Include remote printer adapter",
          "status": "pending",
          "conclusion": null,
          "number": 19,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Include signed virtual display driver",
          "status": "pending",
          "conclusion": null,
          "number": 20,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Verify Flutter font assets",
          "status": "pending",
          "conclusion": null,
          "number": 21,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Sign executable with LDesk icon",
          "status": "pending",
          "conclusion": null,
          "number": 22,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Build portable packer",
          "status": "pending",
          "conclusion": null,
          "number": 23,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Verify portable relaunch keeps the running instance intact",
          "status": "pending",
          "conclusion": null,
          "number": 24,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Smoke test Windows main window responsiveness",
          "status": "pending",
          "conclusion": null,
          "number": 25,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Verify Windows version metadata",
          "status": "pending",
          "conclusion": null,
          "number": 26,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Build x64 installer",
          "status": "pending",
          "conclusion": null,
          "number": 27,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Rename portable EXE for release",
          "status": "pending",
          "conclusion": null,
          "number": 28,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload x64 Windows artifacts",
          "status": "pending",
          "conclusion": null,
          "number": 29,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload x86 service artifacts",
          "status": "pending",
          "conclusion": null,
          "number": 30,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload runtime logs (always)",
          "status": "pending",
          "conclusion": null,
          "number": 31,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Upload to v3.1.1 Release (x64 only)",
          "status": "pending",
          "conclusion": null,
          "number": 32,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Cache vcpkg installed packages",
          "status": "pending",
          "conclusion": null,
          "number": 61,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Setup Flutter",
          "status": "pending",
          "conclusion": null,
          "number": 62,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Cache Cargo registry",
          "status": "pending",
          "conclusion": null,
          "number": 63,
          "started_at": null,
          "completed_at": null
        },
        {
          "name": "Post Run actions/checkout@v4",
          "status": "pending",
          "conclusion": null,
          "number": 64,
          "started_at": null,
          "completed_at": null
        }
      ],
      "check_run_url": "https://api.github.com/repos/luoda2023/LUODA-v3.0.1/check-runs/89884262754",
      "labels": [
        "windows-2022"
      ],
      "runner_id": 1000018060,
      "runner_name": "GitHub Actions 1000018060",
      "runner_group_id": 0,
      "runner_group_name": "GitHub Actions"
    }
  ]
}

```