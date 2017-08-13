## Discourse Instructor Endorsed
This is a <a href="https://www.discourse.org/">Discourse</a> plugin. It is a modified version of the <a href="https://github.com/discourse/discourse-solved">Discourse Solved plugin</a>. It provides an endorse button on categories for instructor level users. This is for use in a school style discourse forum enabling instructors endorse a response to a question. 

![selection_023](https://user-images.githubusercontent.com/24629960/29245733-a26b1bf8-7fb1-11e7-970d-54da4028a4ed.png)

## Installation

### Docker installation
As seen in a [how-to on meta.discourse.org](https://meta.discourse.org/t/advanced-troubleshooting-with-docker/15927#Example:%20Install%20a%20plugin), add this repository's `git clone` url to your container's `app.yml` file, at the bottom of the `cmd` section:

```yml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - mkdir -p plugins
          - git clone https://github.com/bolariin/discourse-instructor-endorsed.git
```
rebuild your container:

```
cd /var/discourse
git pull
./launcher rebuild app
```

### Non-docker installation
* Run `bundle exec rake plugin:install repo=https://github.com/bolariin/discourse-instructor-endorsed.git` in your discourse directory
* In development mode, run `bundle exec rake assets:clean`
* In production, recompile your assets: `bundle exec rake assets:precompile`
* Restart Discourse

### Local Development Installation
* Clone the [Discourse Instructor Endorsed Repo](http://github.com/bolariin/discourse-instructor-endorsed) in a new local folder.
* Separately clone [Discourse Forum](https://github.com/discourse/discourse) in another local folder and [install Discourse](https://meta.discourse.org/t/beginners-guide-to-install-discourse-on-ubuntu-for-development/14727).
* In your terminal, go into Discourse folder navigate into the plugins folder.  Example ```cd ~/code/discourse/plugins```
* Create a symlink in this folder by typing the following into your terminal
```
ln -s ~/whereever_your_cloned_ad_plugin_path_is .
For example: ln -s ~/discourse-plugin-test .
```
* You can now make changes in your locally held Discourse Response Bot folder and see the effect of your changes when your run ```rails s``` in your locally held Discourse Forum files.

## Getting Started
* By default, most of settings have been enabled
![selection_021](https://user-images.githubusercontent.com/24629960/29245761-3dcf2e5e-7fb2-11e7-95df-4cb4da6c4ac8.png)

### Tips and Tricks
* For endorsement trust level, the admin is expected to put the minimum trust level of an instructor in the box

* Using endorsed topics auto close hours, the admin can close a topic after a post has been endorsed. By typing an integer, n, greater than zero in the box, a topic can be closed n hours after a post has been endorsed.

* There is an endorsed section in activities. It helps you keep track of posts you made that are endorsed by instructors
![selection_027](https://user-images.githubusercontent.com/24629960/29245740-b06e3bae-7fb1-11e7-8ca7-7e51e14adc33.png)

* If you wish to allow instructors endorse in select categories, you can acheive this
  * You acheive this by unselecting "allow endorsement on all topics"
  ![selection_025](https://user-images.githubusercontent.com/24629960/29245736-a9cb5264-7fb1-11e7-8475-e6f1df6127ef.png)
  
  * Then proceed to the category settings of your select category
  
  * In the category settings of the select category, enable "Allow instructors to endorse solutions in this category"
  ![selection_026](https://user-images.githubusercontent.com/24629960/29245846-ae5e7ff6-7fb4-11e7-9e84-7752453c9ac6.png)

## License
MIT

