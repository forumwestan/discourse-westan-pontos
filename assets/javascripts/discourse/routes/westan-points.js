import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class WestanPointsRoute extends DiscourseRoute {
  async model() {
    return await ajax("/westan/pontos");
  }
}
