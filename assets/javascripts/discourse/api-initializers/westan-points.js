import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.8.0", (api) => {
  if (!api.getCurrentUser()) {
    return;
  }

  api.addCommunitySectionLink?.({
    name: "westan-points",
    route: "westan-points",
    title: "Pontos e benefícios",
    text: "Meus pontos",
    icon: "coins",
  });
});
