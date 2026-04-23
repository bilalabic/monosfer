module.exports = {
  apps: [
    {
      name: "monad-backend",
      cwd: "/home/yusuf/projects/monad/backend",
      script: "npm",
      args: "run start",
      env: {
        NODE_ENV: "production",
      },
    },
    {
      name: "monad-frontend",
      cwd: "/home/yusuf/projects/monad/frontend",
      script: "npm",
      args: "run preview -- --host 127.0.0.1 --port 3020",
      env: {
        NODE_ENV: "production",
      },
    },
  ],
};
