import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

export default class WestanPointsConfigRoute extends DiscourseRoute {
  beforeModel() {
    if (!this.currentUser) {
      return this.router.transitionTo("login");
    }
    if (!this.currentUser.admin && !this.currentUser.moderator) {
      return this.router.transitionTo("westan-points");
    }
  }

  async model() {
    return await ajax("/westan/pontos/admin/config");
  }
}
