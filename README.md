# Installation OpenStack - CentOS 7.3
<!-- vim-markdown-toc GFM -->
* [Arch](#arch)
* [简介](#简介)
* [使用](#使用)
* [版本](#版本)
* [参加步骤](#参加步骤)

<!-- vim-markdown-toc -->
## Arch

![Screenshot](./doc/images/env/networklayout.png)

## 简介

- 部署环境：Centos 7.3（两台）
- 架构 Controller + Compute
- Core services:
	+ Keystone
	+ Nova
	+ Glance
	+ Neutron
	+ Horizon
	+ Swift (in test)
	+ Cinder (controller only) 
- 本项目根据官方脚本进行更新和定期维护

## 使用

请先阅读([官网](https://docs.openstack.org/))，理解，然后行动(初次使用时，先手动部署一遍，然后使用本程序进行部署)

> * [使用手册](https://github.com/BillWang139967/openstack_install/wiki)
> * [提交 Bug](https://github.com/BillWang139967/openstack_install/issues)

## 版本

* v1.1.1 2017-12-02 更新：更新版本为 Ocata
* v1.0.1 2017-07-20 新增：初始版本 (Mitaka)

## 参加步骤

* 在 GitHub 上 `fork` 到自己的仓库，然后 `clone` 到本地，并设置用户信息。
```
$ git clone https://github.com/BillWang139967/openstack_install.git
$ cd openstack_install
$ git config user.name "yourname"
$ git config user.email "your email"
```
* 修改代码后提交，并推送到自己的仓库。
```
$ #do some change on the content
$ git commit -am "Fix issue #1: change helo to hello"
$ git push
```
* 在 GitHub 网站上提交 pull request。
* 定期使用项目仓库内容更新自己仓库内容。
```
$ git remote add upstream https://github.com/BillWang139967/openstack_install.git
$ git fetch upstream
$ git checkout master
$ git rebase upstream/master
$ git push -f origin master
```
