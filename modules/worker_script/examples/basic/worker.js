export default {
  async fetch(request, env) {
    return new Response("Hello from the example Worker.");
  },

  async scheduled(event, env, ctx) {},
};
