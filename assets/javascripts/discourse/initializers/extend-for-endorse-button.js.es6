import Topic from 'discourse/models/topic';
import User from 'discourse/models/user';
import TopicStatus from 'discourse/raw-views/topic-status';
import { popupAjaxError } from 'discourse/lib/ajax-error';
import { withPluginApi } from 'discourse/lib/plugin-api';
import { ajax } from 'discourse/lib/ajax';
import PostCooked from 'discourse/widgets/post-cooked';

function clearEndorsed(topic) {
  const posts = topic.get('postStream.posts');
  posts.forEach(post => {
    if (post.get('post_number') > 1 ) {
      post.set('endorsed_answer',false);
      post.set('can_endorse_answer',true);
      post.set('can_unendorse_answer',false);
    }
  });
}

function unendorsePost(post) {
  if (!post.get('can_unendorse_answer')) { return; }
  const topic = post.topic;

  post.setProperties({
    can_endorse_answer: true,
    can_unendorse_answer: false,
    endorsed_answer: false
  });
  topic.set('endorsed_answer', undefined);

  ajax("/solution/unendorse", {
    type: 'POST',
    data: { id: post.get('id') }
  }).catch(popupAjaxError);
}

function endorsePost(post) {
  const topic = post.topic;

  clearEndorsed(topic);

  post.setProperties({
    can_unendorse_answer: true,
    can_endorse_answer: false,
    endorsed_answer: true
  });

  topic.set('endorsed_answer', {
    username: post.get('username'),
    post_number: post.get('post_number'),
    excerpt: post.get('cooked'),
    name: post.get('name')
  });

  ajax("/solution/endorse", {
    type: 'POST',
    data: { id: post.get('id') }
  }).catch(popupAjaxError);
}

function initializeWithApi(api) {
  const currentUser = api.getCurrentUser();

  api.includePostAttributes('can_endorse_answer', 'can_unendorse_answer', 'endorsed_answer');  

  if (api.addDiscoveryQueryParam) {
    api.addDiscoveryQueryParam('endorsed', {replace: true, refreshModel: true});
  }

  api.addPostMenuButton('endorsed', attrs => {
    const canEndorse = attrs.can_endorse_answer;
    const canUnendorse = attrs.can_unendorse_answer;
    const endorsed = attrs.endorsed_answer;
    const position = 'first';

    if (canEndorse) {
      return {
        action: 'endorseAnswer',
        icon: 'thumbs-up',
        className: 'unaccepted',
        title: 'endorsed.endorse_answer',
        position
      };
    } else if (canUnendorse || endorsed) {
      const title = canUnendorse ? 'endorsed.unendorse_answer' : 'endorse.endorsed_answer';
      return {
        action: 'unendorseAnswer',
        icon: 'thumbs-up',
        title,
        className: 'accepted fade-out',
        position,
        beforeButton(h) {
          return h('span.accepted-text', I18n.t('endorsed.solution'));
        }
      };
    }
  });

  api.decorateWidget('post-contents:after-cooked', dec => {
    if (dec.attrs.post_number === 1) {
      const postModel = dec.getModel();
      if (postModel) {
        const topic = postModel.get('topic');
        if (topic.get('endorsed_answer')) {

          var rawhtml = `
            <aside class='quote' data-post="${topic.get('endorsed_answer').post_number}" data-topic="${topic.get('id')}">
              <div class='title'>
                ${topic.get('endorsedAnswerHtml')} <div class="quote-controls"><\/div>
              </div>
              <blockquote>
                ${topic.get('endorsed_answer').excerpt}
              </blockquote>
            </aside>`

          var cooked = new PostCooked({cooked:rawhtml});

          var html = cooked.init();

          return dec.rawHtml(html);
        }
      }
    }
  });

  api.attachWidgetAction('post', 'endorseAnswer', function() {
    const post = this.model;
    const current = post.get('topic.postStream.posts').filter(p => {
      return p.get('post_number') === 1 || p.get('endorsed_answer');
    });
    endorsePost(post);

    current.forEach(p => this.appEvents.trigger('post-stream:refresh', { id: p.id }));
  });

  api.attachWidgetAction('post', 'unendorseAnswer', function() {
    const post = this.model;
    const op = post.get('topic.postStream.posts').find(p => p.get('post_number') === 1);
    unendorsePost(post);
    this.appEvents.trigger('post-stream:refresh', { id: op.get('id') });
  });

  if (api.registerConnectorClass) {
    api.registerConnectorClass('user-activity-bottom', 'endorsed-list', {
      shouldRender(args, component) {
        return component.siteSettings.endorse_enabled;
      },
    });

    api.registerConnectorClass('user-summary-stat', 'endorsed-count', {
      shouldRender(args, component) {
        return component.siteSettings.endorse_enabled && args.model.endorsed_count > 0;
      },
      setupComponent() {
        this.set('classNames', ['linked-stat']);
      }
    });
  }
}

export default {
  name: 'extend-for-endorse-button',
  initialize() {

    Topic.reopen({
      // keeping this here cause there is complex localization
      endorsedAnswerHtml: function() {
        const username = this.get('endorsed_answer.username'); // change something here
        const name = this.get('endorsed_answer.name');
        const postNumber = this.get('endorsed_answer.post_number');

        if (!username || !postNumber) {
          return "";
        }

        return I18n.t("endorsed.endorsed_html", {
          username_lower: username.toLowerCase(),
          username,
          post_path: this.get('url') + "/" + postNumber,
          post_number: postNumber,
          user_path: User.create({username: username}).get('path'),
          name: name,
        });
      }.property('endorsed_answer', 'id')
    });

    TopicStatus.reopen({
      statuses: function(){
        const results = this._super();
        if (this.topic.has_endorsed_answer) {
          results.push({
            openTag: 'span',
            closeTag: 'span',
            title: I18n.t('endorsed.has_endorsed_answer'),
            icon: 'thumbs-up'
          });
        }else if(this.topic.can_be_endorsed && this.siteSettings.endorse_enabled && this.siteSettings.circle_on_unendorsed){
          results.push({
            openTag: 'span',
            closeTag: 'span',
            title: I18n.t('endorsed.has_no_endorsed_answer'),
            icon: 'circle-o'
          });
        }
        return results;
      }.property()
    });

    withPluginApi('0.1', initializeWithApi);
  }
};
